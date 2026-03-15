#!/usr/bin/env python3
import asyncio
import json
import os
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse, StreamingResponse


def _bool_env(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


MODEL_UPSTREAMS = {
    "small": os.getenv("UPSTREAM_SMALL", "http://127.0.0.1:8003"),
    "medium": os.getenv("UPSTREAM_MEDIUM", "http://127.0.0.1:8000"),
    "large": os.getenv("UPSTREAM_LARGE", "http://127.0.0.1:8002"),
}
MODEL_TARGET_IDS = {
    "small": os.getenv("MODEL_ID_SMALL", "nvidia/Llama-3.1-8B-Instruct-NVFP4"),
    "medium": os.getenv("MODEL_ID_MEDIUM", "nvidia/Qwen3-30B-A3B-NVFP4"),
    "large": os.getenv("MODEL_ID_LARGE", "nvidia/Llama-3.3-70B-Instruct-NVFP4"),
}
DEFAULT_MODEL_ALIAS = os.getenv("DEFAULT_MODEL_ALIAS", "medium")
REQUEST_TIMEOUT = float(os.getenv("GATEWAY_TIMEOUT_SECONDS", "600"))
UPSTREAM_HEALTHCHECK_TIMEOUT = float(os.getenv("UPSTREAM_HEALTHCHECK_TIMEOUT_SECONDS", "1.5"))
SIZE_ORDER = {"small": 0, "medium": 1, "large": 2}

if DEFAULT_MODEL_ALIAS not in MODEL_UPSTREAMS:
    raise RuntimeError(
        f"DEFAULT_MODEL_ALIAS must be one of {sorted(MODEL_UPSTREAMS)}; got {DEFAULT_MODEL_ALIAS!r}"
    )

app = FastAPI(title="vLLM Alias Gateway", version="0.1.0")


@app.on_event("startup")
async def startup() -> None:
    app.state.http = httpx.AsyncClient(timeout=REQUEST_TIMEOUT)


@app.on_event("shutdown")
async def shutdown() -> None:
    await app.state.http.aclose()


def _outbound_headers(request: Request) -> dict[str, str]:
    blocked = {"host", "content-length", "connection"}
    return {k: v for k, v in request.headers.items() if k.lower() not in blocked}


async def _is_upstream_alive(client: httpx.AsyncClient, alias: str) -> bool:
    url = f"{MODEL_UPSTREAMS[alias]}/v1/models"
    try:
        resp = await client.get(url, timeout=UPSTREAM_HEALTHCHECK_TIMEOUT)
        return resp.status_code == 200
    except Exception:
        return False


async def _select_default_alias(client: httpx.AsyncClient) -> str:
    aliases = list(MODEL_UPSTREAMS.keys())
    checks = await asyncio.gather(*[_is_upstream_alive(client, a) for a in aliases])
    alive = [a for a, ok in zip(aliases, checks) if ok]
    if not alive:
        return DEFAULT_MODEL_ALIAS
    alive.sort(key=lambda a: SIZE_ORDER.get(a, 999))
    return alive[0]


def _alias_models_payload() -> dict[str, Any]:
    data = []
    for alias in MODEL_UPSTREAMS:
        data.append(
            {
                "id": alias,
                "object": "model",
                "owned_by": "gateway",
                "root": alias,
                "upstream_model": MODEL_TARGET_IDS[alias],
                "permission": [],
            }
        )
    return {"object": "list", "data": data, "default": DEFAULT_MODEL_ALIAS}


@app.get("/health")
async def health() -> dict[str, Any]:
    client: httpx.AsyncClient = app.state.http
    chosen_default = await _select_default_alias(client)
    return {
        "ok": True,
        "configured_default_model": DEFAULT_MODEL_ALIAS,
        "effective_default_model": chosen_default,
        "models": sorted(MODEL_UPSTREAMS),
    }


@app.get("/v1/models")
async def models() -> dict[str, Any]:
    return _alias_models_payload()


@app.api_route("/v1/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy_v1(path: str, request: Request) -> Response:
    if path == "models" and request.method == "GET":
        return JSONResponse(_alias_models_payload())

    body = await request.body()
    chosen_model = DEFAULT_MODEL_ALIAS
    rewritten_body = body
    wants_stream = False
    is_json = "application/json" in request.headers.get("content-type", "")

    if is_json and body:
        try:
            payload = json.loads(body)
        except json.JSONDecodeError as exc:
            raise HTTPException(status_code=400, detail=f"Invalid JSON body: {exc}") from exc
        if isinstance(payload, dict):
            wants_stream = bool(payload.get("stream", False))
            client: httpx.AsyncClient = app.state.http
            if "model" not in payload or payload["model"] in (None, ""):
                chosen_model = await _select_default_alias(client)
                payload["model"] = MODEL_TARGET_IDS[chosen_model]
            elif payload["model"] in MODEL_UPSTREAMS:
                requested = payload["model"]
                chosen_model = requested
                payload["model"] = MODEL_TARGET_IDS[requested]
            else:
                # Unknown model values are treated as unset and use the smallest available model.
                chosen_model = await _select_default_alias(client)
                payload["model"] = MODEL_TARGET_IDS[chosen_model]
            rewritten_body = json.dumps(payload).encode("utf-8")

    base = MODEL_UPSTREAMS[chosen_model]
    url = f"{base}/v1/{path}"
    method = request.method.upper()
    headers = _outbound_headers(request)

    if is_json:
        headers["content-length"] = str(len(rewritten_body))

    client: httpx.AsyncClient = app.state.http
    if wants_stream:
        upstream = client.build_request(method, url, content=rewritten_body, headers=headers)
        stream = await client.send(upstream, stream=True)

        async def body_iter():
            try:
                async for chunk in stream.aiter_raw():
                    yield chunk
            finally:
                await stream.aclose()

        response_headers = {
            k: v
            for k, v in stream.headers.items()
            if k.lower() not in {"content-length", "connection", "transfer-encoding"}
        }
        return StreamingResponse(
            body_iter(),
            status_code=stream.status_code,
            headers=response_headers,
            media_type=stream.headers.get("content-type"),
        )

    upstream = await client.request(method, url, content=rewritten_body, headers=headers)
    response_headers = {
        k: v
        for k, v in upstream.headers.items()
        if k.lower() not in {"content-length", "connection", "transfer-encoding"}
    }
    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        headers=response_headers,
        media_type=upstream.headers.get("content-type"),
    )
