#!/usr/bin/env bash
# modelctl.sh — manage the active vLLM container on DGX Spark
#
# Usage:
#   ./modelctl.sh start 30b|70b
#   ./modelctl.sh stop
#   ./modelctl.sh status
#   ./modelctl.sh logs
#
# Committed by Keystone with love ❤️

set -euo pipefail

IMAGE_TAG="nvcr.io/nvidia/vllm:26.01-py3"
CONTAINER_NAME="vllm-active"
PORT="8000"
HF_CACHE="${HOME}/.cache/huggingface"

MODEL_30B="nvidia/Qwen3-30B-A3B-NVFP4"
MODEL_70B="nvidia/Llama-3.3-70B-Instruct-NVFP4"

color() { local c=$1; shift; echo -e "\033[${c}m$*\033[0m"; }
info()  { color 36 "$*"; }
err()   { color 31 "$*" >&2; }

running() {
  docker ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}" || return 1
}

start_model() {
  local model=$1
  local model_id="${MODEL_30B}"
  if [[ $model == 70b ]]; then
    model_id="${MODEL_70B}"
  fi

  if running; then
    info "Stopping existing container …"
    docker stop "${CONTAINER_NAME}" > /dev/null
  fi

  info "Starting ${model} container (${model_id}) …"
  docker run -d --name "${CONTAINER_NAME}" \
    --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 \
    -p "${PORT}:8000" \
    -v "${HF_CACHE}:/root/.cache/huggingface" \
    "${IMAGE_TAG}" \
    vllm serve "${model_id}" > /dev/null

  info "Waiting for model to load …"
  for i in {1..120}; do
    if curl -s "http://localhost:${PORT}/v1/models" | grep -q "${model_id}"; then
      info "Model is ready!"
      return 0
    fi
    sleep 2
  done
  err "Timed out waiting for model to load. Check logs."
  exit 1
}

case "${1-}" in
  start)
    [[ $# -eq 2 && ( $2 == 30b || $2 == 70b ) ]] || { err "Usage: $0 start 30b|70b"; exit 1; }
    start_model "$2"
    ;;
  stop)
    if running; then
      info "Stopping container …" && docker stop "${CONTAINER_NAME}"
    else
      info "No container is running."
    fi
    ;;
  status)
    if running; then
      info "Active container:" && docker ps --filter "name=${CONTAINER_NAME}"
    else
      info "No container is running."
    fi
    ;;
  logs)
    if running; then
      docker logs -f "${CONTAINER_NAME}"
    else
      err "No running container to tail logs from."
      exit 1
    fi
    ;;
  *)
    err "Unknown command. Usage: $0 start 30b|70b | stop | status | logs"
    exit 1
    ;;
esac
