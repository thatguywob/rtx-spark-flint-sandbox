# Contributing to RTX Spark Flint Sandbox

Thank you for your interest in contributing! This project provides a reproducible, CNCF OCI-compliant, and microVM-isolated local serving environment for **Flint NVFP4** on Windows 11 ARM64 (NVIDIA Blackwell RTX GPU, SM 12.1a).

We welcome issues, feature suggestions, documentation enhancements, and pull requests that align with our core architectural and security standards.

---

## 1. Core Principles

All contributions must adhere to the following principles:

1. **Hive Commons Sandbox Compliance:**  
   Inference runtimes are treated as untrusted code executors. Changes must preserve:
   - **Credential-free confinement:** Zero host tokens, SSH keys, or write permissions inside containers.
   - **Read-only weights:** Model weights must remain bind-mounted strictly read-only (`:ro`).
   - **Loopback-only ingress:** Ingress must be restricted to host loopback (`127.0.0.1:8080`).
   - **Binary-level egress elimination:** `llama-server` must compile with `-DLLAMA_CURL=OFF`.
   - **Unprivileged execution:** Non-root user execution (`UID:GID 1000:1000`) and non-executable scratch storage (`/tmp tmpfs 1G,noexec,nosuid`).
2. **Fedora / Enterprise Linux Toolchain (Non-Ubuntu):**  
   We deliberately avoid upstream prebuilt Ubuntu binaries. Container definitions must use pinned Fedora / CentOS Stream SBSA toolchains.
3. **Reproducibility & Digest Pinning:**  
   Base container images, source release tarballs, and model revisions must be pinned to explicit cryptographic SHA-256 digests. Floating tags (such as `:latest`) are not accepted.
4. **Zero Host Pollution:**  
   Do not add tasks that write unmanaged binaries to host `%LOCALAPPDATA%` or modify system-wide registry/PATH settings. All runtime artifacts must live within the container or user-controlled `.env` configuration.

---

## 2. Development Setup

### Prerequisites
- **Workstation:** Windows 11 ARM64 with an NVIDIA Blackwell RTX GPU (SM 12.1a) and CUDA 13.5+ driver.
- **Runtimes:** WSL2 with `wslc` (v3.0.3+) installed.
- **Task Runner:** `mise` (for cross-platform task orchestration) and `uv` (for Python test execution).

### Local Setup
1. Fork the repository on GitHub and clone your fork:
   ```bash
   git clone https://github.com/<your-username>/rtx-spark-flint-sandbox.git
   cd rtx-spark-flint-sandbox
   ```
2. Create your local environment configuration:
   ```bash
   cp .env.example .env
   ```
3. Edit `.env` to point `MODEL_PATH` to your local `flint-nvfp4.gguf` file and set a secure `FLINT_API_KEY`.  
   *(Note: `.env` is ignored by `.gitignore` and must never be committed).*

---

## 3. Working with Tasks (`mise`)

We use `mise` to maintain reproducible workflows across both Windows PowerShell and WSL Linux:

| Task | Command | Description |
| :--- | :--- | :--- |
| **Verify Model** | `mise run model:verify` | Cryptographically checks weight file size and SHA-256 digest |
| **Build Image** | `mise run sandbox:build` | Compiles `llama-server` from source inside CentOS 10 $\rightarrow$ Fedora 45 |
| **Start Container**| `mise run sandbox:start` | Launches detached container with GPU passthrough |
| **Wait for Ready** | `mise run sandbox:wait` | Polls `/health` endpoint until model loading completes |
| **Run Smoke Test** | `mise run sandbox:smoke` | Validates 401 auth gate, streaming tokens, and reasoning retention |
| **Check Telemetry**| `mise run sandbox:status`| Displays live container memory, CPU stats (`wslc stats`), and health |
| **Restart** | `mise run sandbox:restart`| Sequentially stops, starts, and waits for container readiness |
| **Stop** | `mise run sandbox:stop` | Idempotently stops container and frees GPU memory |

---

## 4. Pull Request Checklist

Before opening a pull request, ensure:

- [ ] **No Secrets or Paths:** Verify that no private API keys, machine names, personal emails, or hardcoded user home directories appear in your changes.
- [ ] **No Model Weights:** Verify that no `.gguf` or large binary files are staged.
- [ ] **Smoke Test Passes:** Run `mise run sandbox:smoke` and confirm all assertions succeed:
  - Pre-flight unauthenticated probe returns `HTTP 401 Unauthorized`.
  - Authenticated streaming produces tokens and retains `<think>` reasoning traces.
- [ ] **Script Portability:** Ensure any modified PowerShell or Bash scripts propagate failure exit codes (`exit $LASTEXITCODE`) and handle missing environment variables gracefully.
- [ ] **Documentation Updated:** Update `README.md`, `ARCHITECTURE.md`, or `TROUBLESHOOTING.md` if your change modifies configuration options, ports, or flags.

---

## 5. Reporting Issues

- **Bug Reports:** Please describe the issue, provide the exact steps to reproduce, and include relevant logs from `mise run sandbox:status` or `mise run sandbox:logs`. Redact any private IP addresses, domains, or keys before posting.
- **Feature Requests:** Open an issue outlining the motivation, technical approach, and how it aligns with Hive Commons isolation standards.
