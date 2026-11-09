# Flint-nvfp4 Sandboxed OCI Serving on NVIDIA RTX Spark

[![OCI Standard](https://img.shields.io/badge/OCI-Container-blue.svg)](https://opencontainers.org/)
[![Fedora](https://img.shields.io/badge/Fedora-45_Stable-51A2DA.svg)](https://fedoraproject.org/)
[![CUDA](https://img.shields.io/badge/CUDA-13.5_SBSA-76B900.svg)](https://developer.nvidia.com/cuda-toolkit)
[![Architecture](https://img.shields.io/badge/Arch-ARM64_%2F_Blackwell_SM12.1a-green.svg)](https://developer.nvidia.com)
[![Hive Commons](https://img.shields.io/badge/Hive_Commons-Sandbox_Isolation-orange.svg)](https://github.com/hivecommons/hive)

Sandboxed, reproducible, and credential-free serving of **Flint NVFP4** (`RecursiveSI/flint-nvfp4-gguf`) inside a Fedora 45 OCI container on Windows 11 ARM64 (NVIDIA RTX Spark N1X Blackwell GPU, SM 12.1a, CUDA 13.5). Orchestrated via `mise` and Microsoft's `wslc` (WSL Containers).

---

## Architecture & Isolation Boundaries

```
[Client / omp / Tailnet HTTPS]
              │
              ▼
    [Windows Host Loopback] (127.0.0.1:8080)
              │
   ┌──────────▼─────────────────────────────────────────────────┐
   │ Hyper-V Hypervisor Boundary (WSL2 Linux Utility VM)        │
   │                                                            │
   │   /dev/dxg (Direct3D / CUDA UMD Paravirtualization)        │
   │      │                                                     │
   │   ┌──▼──────────────────────────────────────────────────┐  │
   │   │ Sandboxed Fedora 45 OCI Container (runc)            │  │
   │   │                                                     │  │
   │   │  • Unprivileged non-root user (UID:GID 1000:1000)   │  │
   │   │  • Read-only model weights mount (:ro)              │  │
   │   │  • Volatile scratch (/tmp tmpfs 1G, noexec, nosuid) │  │
   │   │  • Egress eliminated (-DLLAMA_CURL=OFF)             │  │
   │   │  • 20 OpenMP CPU worker threads (libgomp.so.1)      │  │
   │   │  • 50/50 layers offloaded to CUDA0 (SM 12.1a FP4)   │  │
   │   └─────────────────────────────────────────────────────┘  │
   └────────────────────────────────────────────────────────────┘
```

### Hive Commons Sandbox Isolation Compliance
1. **MicroVM Boundary Isolation:** Leverages WSL2's Hyper-V hypervisor boundary to separate the containerized Linux inference process from the Windows NT host kernel.
2. **Loopback-Only Ingress & Authentication:** Published strictly to `127.0.0.1:8080:8080`. All HTTP requests require Bearer token authorization (`Authorization: Bearer <FLINT_API_KEY>`), rejecting unauthenticated requests with `HTTP 401 Unauthorized`.
3. **Binary Hardening (Egress Elimination):** `llama-server` is compiled with `-DLLAMA_CURL=OFF`, completely removing HTTP/HTTPS client networking from the executable (application-level binary hardening; the container image retains utilities such as `curl` for container healthchecks).
4. **Credential-Free & Read-Only Weights:** Zero host credentials or tokens enter the container; model weights are mounted strictly read-only (`:ro`).
5. **Least Privilege & Quotas:** Unprivileged user execution (`1000:1000`), volatile non-executable tmpfs scratch at `/tmp` (`size=1G,noexec,nosuid`), and `--memory 48G` cgroup ceiling.

---

## Prerequisites

- **Host:** Windows 11 ARM64 (Snapdragon / NVIDIA Blackwell GPU, CUDA 13.5 driver).
- **WSL:** WSL2 with `wslc` (`Windows Subsystem for Linux Container CLI` v3.0.3+).
- **Tools:** `mise` (task runner) and `uv` (fast Python runner for verification).

---

## Quickstart

### 1. Configure Local Environment
Copy the example environment configuration to `.env` and set your local model file path:
```bash
cp .env.example .env
```
Edit `.env`:
```dotenv
MODEL_PATH=C:/models/flint-nvfp4.gguf
FLINT_API_KEY=your-secure-local-api-key-here
PORT=8080
```

### 2. Verify Model Integrity
Cryptographically validate file size (22,863,084,160 bytes) and SHA-256 digest before building:
```bash
mise run model:verify
```

### 3. Build the Fedora 45 OCI Container
Compiles `llama-server` from source on CentOS Stream 10 + CUDA 13.5 SBSA, targeting Blackwell SM 12.1a with native FP4 acceleration, and packages into a minimal Fedora 45 stable runtime image:
```bash
mise run sandbox:build
```

### 4. Start the Sandbox
Launch the container in background detached mode:
```bash
mise run sandbox:start
```

### 5. Run Verification & Health Checks
Wait for readiness and run the automated streaming compliance and token velocity smoke test:
```bash
mise run sandbox:smoke
```

---

## Lifecycle Commands (`mise`)

| Command | Action |
| :--- | :--- |
| `mise run sandbox:status` | Display container state, live memory/CPU stats (`wslc stats`), and health status |
| `mise run sandbox:restart` | Sequentially stop, start, and poll container until healthy |
| `mise run sandbox:smoke` | Run automated security probe (401 gate) and streaming token velocity test |
| `mise run sandbox:logs` | View container inference logs (`--log-verbosity 4`) |
| `mise run sandbox:stop` | Idempotently stop the container and release GPU VRAM |
| `mise run sandbox:serve` | Run the container in foreground interactive mode |
---

## Tailscale Serve Integration (Zero-Trust Remote Access)

To securely share the endpoint across your private Tailnet without exposing LAN ports:

1. On the Windows host, configure `tailscale serve` to proxy incoming HTTPS to the loopback port:
   ```powershell
   tailscale serve --bg http://127.0.0.1:8080
   ```
2. Set `TAILNET_ENDPOINT=https://<node-name>.<tailnet-name>.ts.net` in your `.env`.
3. Remote clients connect with TLS 1.3 encryption and Bearer authentication:
   ```bash
   curl -H "Authorization: Bearer <FLINT_API_KEY>" https://<node-name>.<tailnet-name>.ts.net/v1/models
   ```

---

## Client Integration (`omp`)

In your client's `models.yml` (e.g. `~/.omp/agent/models.yml`):

```yaml
providers:
  flint-sandbox:
    baseUrl: http://127.0.0.1:8080/v1 # or https://<node-name>.<tailnet-name>.ts.net/v1
    apiKey: your-secure-local-api-key-here
    api: openai-completions
    compat:
      supportsStore: false
      supportsDeveloperRole: false
      supportsReasoningEffort: false
      maxTokensField: max_tokens
      reasoningContentField: reasoning_content
      requiresReasoningContentForToolCalls: true
      allowsSyntheticReasoningContentForToolCalls: false
    models:
      - id: flint
        name: Flint NVFP4 (Sandboxed OCI)
        reasoning: true
        input: [text]
        contextWindow: 65536
        maxTokens: 32768
        cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}
```

---

## License

This project is licensed under the Apache-2.0 License. Model weights and third-party dependencies are subject to their respective upstream licenses.
