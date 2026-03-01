# Spark Dev AI Engineering Lab

This repository houses all scripts, configuration, and documentation required to operate the on-prem DGX "Spark" AI engineering lab.

## Purpose

1. **Model Lifecycle Management** – Shell scripts or Docker Compose files to start, stop, and switch between local vLLM containers (e.g., 30 B and 70 B models) served via an OpenAI-compatible HTTP API.
2. **Automation & Orchestration** – Utilities and agents (including the Keystone assistant) that decide when to switch models, proxy traffic, and monitor health.
3. **Infrastructure as Code** – Version-controlled Nginx/FastAPI proxy configs, Prometheus/Grafana monitoring setup, and any Kubernetes (k3s) manifests if we move beyond bare Docker.
4. **Documentation** – Architecture diagrams, operating procedures, benchmarking results, and tuning guides.

## Immediate Roadmap

- [x] Create repo skeleton and this README
- [ ] Add `modelctl` shell script for starting/stopping 30 B & 70 B containers
- [ ] Add lightweight `docker-compose.yml` for both containers
- [ ] Implement proxy layer with model-switch endpoint
- [ ] Define switching heuristics and encode them in the assistant or proxy
- [ ] Set up CI (GitHub Actions) to lint shell scripts and validate compose files

---
*Managed and orchestrated with the help of the Keystone assistant.*
