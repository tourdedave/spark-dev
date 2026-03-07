#!/usr/bin/env bash
# modelctl.sh — manage vLLM containers on DGX Spark
#
# Usage:
#   ./modelctl.sh start [small|medium|large]
#   ./modelctl.sh stop [small|medium|large|all]
#   ./modelctl.sh status [small|medium|large]
#   ./modelctl.sh logs <small|medium|large>
#
set -euo pipefail

IMAGE_TAG="nvcr.io/nvidia/vllm:26.01-py3"
CONTAINER_PREFIX="vllm"
HF_CACHE="${HOME}/.cache/huggingface"
DEFAULT_SIZE="medium"

MODEL_SMALL="nvidia/Llama-3.1-8B-Instruct-NVFP4"
MODEL_MEDIUM="nvidia/Qwen3-30B-A3B-NVFP4"
MODEL_LARGE="nvidia/Llama-3.3-70B-Instruct-NVFP4"

GPU_UTIL_SMALL="0.2"
GPU_UTIL_MEDIUM="0.5"
GPU_UTIL_LARGE="0.8"

PORT_SMALL="8003"
PORT_MEDIUM="8000"
PORT_LARGE="8002"

MAX_MODEL_LEN_SMALL="32768"

STARTUP_TIMEOUT_SECONDS="300"
STARTUP_POLL_INTERVAL_SECONDS="2"

color() { local c=$1; shift; echo -e "\033[${c}m$*\033[0m"; }
info()  { color 36 "$*"; }
err()   { color 31 "$*" >&2; }

usage() {
  err "Usage: $0 start [small|medium|large] | stop [small|medium|large|all] | status [small|medium|large] | logs <small|medium|large>"
  exit 1
}

is_valid_size() {
  case "${1-}" in
    small|medium|large) return 0 ;;
    *) return 1 ;;
  esac
}

container_for_size() {
  echo "${CONTAINER_PREFIX}-$1"
}

model_for_size() {
  case "$1" in
    small) echo "${MODEL_SMALL}" ;;
    medium) echo "${MODEL_MEDIUM}" ;;
    large) echo "${MODEL_LARGE}" ;;
  esac
}

gpu_util_for_size() {
  case "$1" in
    small) echo "${GPU_UTIL_SMALL}" ;;
    medium) echo "${GPU_UTIL_MEDIUM}" ;;
    large) echo "${GPU_UTIL_LARGE}" ;;
  esac
}

max_model_len_for_size() {
  case "$1" in
    small) echo "${MAX_MODEL_LEN_SMALL}" ;;
    medium|large) echo "" ;;
  esac
}

port_for_size() {
  case "$1" in
    small) echo "${PORT_SMALL}" ;;
    medium) echo "${PORT_MEDIUM}" ;;
    large) echo "${PORT_LARGE}" ;;
  esac
}

running() {
  local container_name=$1
  docker ps --filter "name=^/${container_name}$" --format '{{.Names}}' | grep -q "^${container_name}$" || return 1
}

exists() {
  local container_name=$1
  docker ps -a --filter "name=^/${container_name}$" --format '{{.Names}}' | grep -q "^${container_name}$" || return 1
}

start_model() {
  local size=$1
  local container_name
  local model_id
  local gpu_util
  local host_port
  local max_model_len
  local port_owner
  local attempts

  container_name="$(container_for_size "$size")"
  model_id="$(model_for_size "$size")"
  gpu_util="$(gpu_util_for_size "$size")"
  host_port="$(port_for_size "$size")"
  max_model_len="$(max_model_len_for_size "$size")"

  if exists "${container_name}"; then
    info "Removing existing ${container_name} container …"
    docker rm -f "${container_name}" > /dev/null
  fi

  port_owner="$(docker ps --filter "publish=${host_port}" --format '{{.Names}}' | head -n1 || true)"
  if [[ -n "${port_owner}" ]]; then
    err "Port :${host_port} is already in use by ${port_owner}. Stop that container first."
    exit 1
  fi

  info "Starting ${size} container (${container_name}) with ${model_id} on :${host_port} …"
  local -a vllm_args
  vllm_args=(serve "${model_id}" --gpu-memory-utilization "${gpu_util}")
  if [[ -n "${max_model_len}" ]]; then
    vllm_args+=(--max-model-len "${max_model_len}")
  fi

  docker run -d --name "${container_name}" \
    --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 \
    -p "${host_port}:8000" \
    -v "${HF_CACHE}:/root/.cache/huggingface" \
    "${IMAGE_TAG}" \
    vllm "${vllm_args[@]}" > /dev/null

  info "Waiting for ${size} model to load on :${host_port} (timeout: ${STARTUP_TIMEOUT_SECONDS}s) …"
  attempts=$((STARTUP_TIMEOUT_SECONDS / STARTUP_POLL_INTERVAL_SECONDS))
  for ((i=1; i<=attempts; i++)); do
    if curl -s --connect-timeout 2 --max-time 2 "http://localhost:${host_port}/v1/models" | grep -q "${model_id}"; then
      info "${size} model is ready!"
      docker ps --filter "name=^/${container_name}$"
      return 0
    fi
    sleep "${STARTUP_POLL_INTERVAL_SECONDS}"
  done
  err "Timed out waiting for ${size} model after ${STARTUP_TIMEOUT_SECONDS}s."
  docker ps --filter "name=^/${container_name}$"
  err "Check logs with: $0 logs ${size}"
  exit 1
}

stop_model() {
  local size=$1
  local container_name
  container_name="$(container_for_size "$size")"
  if running "${container_name}"; then
    info "Stopping ${container_name} …"
    docker stop "${container_name}" > /dev/null
  else
    info "${container_name} is not running."
  fi
}

stop_all_models() {
  local names
  names="$(docker ps --filter "name=^/${CONTAINER_PREFIX}-" --format '{{.Names}}')"
  if [[ -z "${names}" ]]; then
    info "No ${CONTAINER_PREFIX}-* containers are running."
    return 0
  fi

  info "Stopping all ${CONTAINER_PREFIX}-* containers …"
  # shellcheck disable=SC2086
  docker stop ${names} > /dev/null
}

show_status() {
  local size="${1-}"
  local filter
  local names
  if [[ -n "${size}" ]]; then
    filter="^/$(container_for_size "$size")$"
    info "Status for ${size}:"
    names="$(docker ps --filter "name=${filter}" --format '{{.Names}}')"
    if [[ -z "${names}" ]]; then
      info "$(container_for_size "$size") is not running."
      return 0
    fi
    docker ps --filter "name=${filter}" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    return 0
  fi

  info "Running ${CONTAINER_PREFIX}-* containers:"
  names="$(docker ps --filter "name=^/${CONTAINER_PREFIX}-" --format '{{.Names}}')"
  if [[ -z "${names}" ]]; then
    info "No ${CONTAINER_PREFIX}-* containers are running."
    return 0
  fi
  docker ps --filter "name=^/${CONTAINER_PREFIX}-" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
}

show_logs() {
  local size=$1
  local container_name
  container_name="$(container_for_size "$size")"
  if running "${container_name}"; then
    docker logs -f "${container_name}"
  else
    err "${container_name} is not running."
    exit 1
  fi
}

case "${1-}" in
  start)
    [[ $# -le 2 ]] || usage
    size="${2:-${DEFAULT_SIZE}}"
    is_valid_size "${size}" || usage
    start_model "${size}"
    ;;
  stop)
    [[ $# -le 2 ]] || usage
    target="${2:-all}"
    if [[ "${target}" == "all" ]]; then
      stop_all_models
    else
      is_valid_size "${target}" || usage
      stop_model "${target}"
    fi
    ;;
  status)
    [[ $# -le 2 ]] || usage
    if [[ $# -eq 2 ]]; then
      is_valid_size "${2}" || usage
      show_status "${2}"
    else
      show_status
    fi
    ;;
  logs)
    [[ $# -eq 2 ]] || usage
    is_valid_size "${2}" || usage
    show_logs "${2}"
    ;;
  *)
    usage
    ;;
esac
