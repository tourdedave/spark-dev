# Spark Dev AI Engineering Lab

This repository houses all scripts, configuration, and documentation required to operate the on-prem DGX "Spark" AI engineering lab.

## Purpose

1. **Model Lifecycle Management** – Shell scripts or Docker Compose files to start, stop, and switch between local vLLM containers (e.g., 30 B and 70 B models) served via an OpenAI-compatible HTTP API.
2. **Automation & Orchestration** – Utilities and agents that decide when to switch models, proxy traffic, and monitor health.
3. **Infrastructure as Code** – Version-controlled Nginx/FastAPI proxy configs, Prometheus/Grafana monitoring setup, and any Kubernetes (k3s) manifests if we move beyond bare Docker.
4. **Documentation** – Architecture diagrams, operating procedures, benchmarking results, and tuning guides.

## Lean Gateway (Alias Routing)

Use a single OpenAI-compatible endpoint and route by alias (`small`, `medium`, `large`) instead of port.

### Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r gateway/requirements.txt
```

### Run

```bash
source .venv/bin/activate
uvicorn gateway.app:app --host 0.0.0.0 --port 8080
```

### Optional env vars

```bash
export DEFAULT_MODEL_ALIAS=medium
export UPSTREAM_SMALL=http://127.0.0.1:8003
export UPSTREAM_MEDIUM=http://127.0.0.1:8000
export UPSTREAM_LARGE=http://127.0.0.1:8002
```

### App usage

Point apps to `http://<host>:8080/v1` and set `model` to alias: `small`, `medium`, `large`.
If `model` is omitted or incompatible, the gateway auto-picks the smallest currently available alias (`small` -> `medium` -> `large`). If none are reachable, it falls back to `DEFAULT_MODEL_ALIAS`.
