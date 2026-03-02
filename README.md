# Spark Dev AI Engineering Lab

This repository houses all scripts, configuration, and documentation required to operate the on-prem DGX "Spark" AI engineering lab.

## Purpose

1. **Model Lifecycle Management** – Shell scripts or Docker Compose files to start, stop, and switch between local vLLM containers (e.g., 30 B and 70 B models) served via an OpenAI-compatible HTTP API.
2. **Automation & Orchestration** – Utilities and agents that decide when to switch models, proxy traffic, and monitor health.
3. **Infrastructure as Code** – Version-controlled Nginx/FastAPI proxy configs, Prometheus/Grafana monitoring setup, and any Kubernetes (k3s) manifests if we move beyond bare Docker.
4. **Documentation** – Architecture diagrams, operating procedures, benchmarking results, and tuning guides.
