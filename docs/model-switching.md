# Model Switching Strategy

This document proposes a simple, reliable way to switch between the 30 B and 70 B vLLM containers on the DGX Spark.

## Goals

1. **Single-command UX** – `modelctl start 30b` or `modelctl start 70b`.
2. **Graceful stop** – Ensure the running container shuts down cleanly before the new one starts.
3. **Minimal dependencies** – Pure Bash + Docker (no Compose/K8s) for now.
4. **Extensible** – Easy to add more models later.

## Proposed Tooling

### `scripts/modelctl.sh`
A Bash script living in `scripts/` that supports:

```bash
modelctl.sh start 30b   # start Qwen3-30B container (port 8000)
modelctl.sh start 70b   # start Llama-3.3-70B container (port 8000)
modelctl.sh stop        # stop whatever model container is running
modelctl.sh status      # show running model & its uptime
modelctl.sh logs        # follow logs of the active container
```

Key implementation details:

| Aspect                | Value |
|-----------------------|-------|
| **Container name**    | `vllm-active` (constant). This avoids port conflicts and lets us stop via name. |
| **Image tag**         | `nvcr.io/nvidia/vllm:26.01-py3` |
| **Shared HF cache**   | `~/.cache/huggingface` mounted to `/root/.cache/huggingface` |
| **GPU access**        | `--gpus all` + `--ipc=host` |
| **Ulimits**           | same as your run command |
| **Port**              | `8000` exposed |

### Why not `docker-compose` yet?

Compose is great but introduces an extra layer the first time we switch (compose down/up). Bash keeps it transparent and is friendlier if you ever migrate to systemd services.

If/when we want blue/green or concurrent models, we can graduate to Compose or k3s.

## Script Flow (start <model>)

1. **Detect** if `vllm-active` container is running. If so → `docker stop vllm-active` and wait until exit.
2. **Launch** new container with correct model arg:
   ```bash
   docker run -d --name vllm-active \
     --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 \
     -p 8000:8000 \
     -v "$HF_CACHE:/root/.cache/huggingface" \
     $IMAGE_TAG \
     vllm serve "$MODEL_ID"
   ```
3. **Health check**: poll `http://localhost:8000/v1/models` until the model appears (timeout 120 s).

## Next Steps

1. Implement `scripts/modelctl.sh` + add Makefile alias `make model-30` / `make model-70` for convenience.
2. Update README with usage examples.
3. (Future) Add a small Python/Flask admin endpoint that calls the script so agents can `curl /admin/switch/70b`.

---
