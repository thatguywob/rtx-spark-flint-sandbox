# Troubleshooting & Diagnostics Guide

This guide covers common operational issues, diagnostics, and recovery procedures for the sandboxed Flint-nvfp4 serving environment.

---

## 1. Quick Diagnostic Flowchart

Run the automated status task to inspect all layers at once:

```bash
mise run sandbox:status
```

* If **Container State** is `Stopped` $\rightarrow$ See [Section 2: Container Startup Failures](#2-container-startup-failures).
* If **Healthcheck Status** is `unreachable` or timing out $\rightarrow$ See [Section 3: Healthcheck & Loading Delays](#3-healthcheck--loading-delays).
* If **Smoke Test** returns `HTTP 401 Unauthorized` $\rightarrow$ See [Section 4: Authentication Failures](#4-authentication-failures).
* If **Connecting from WSL** returns `Connection refused` $\rightarrow$ See [Section 5: WSL2 NAT Loopback Behavior](#5-wsl2-nat-loopback-behavior).

---

## 2. Container Startup Failures

### Symptom: `error while loading shared libraries: libcuda.so.1`
* **Cause:** The container was launched without GPU paravirtualization flags, so `/usr/lib/wsl/lib` was not mounted.
* **Fix:** Ensure `--gpus all` is passed to `wslc run`. If running manually, use:
  ```bash
  wslc run -d --rm --gpus all ...
  ```

### Symptom: `bind: address already in use` or Port Conflict
* **Cause:** Another process or a lingering container is listening on port 8080.
* **Fix:**
  1. Check for running containers:
     ```bash
     wslc list
     ```
  2. Stop any existing sandbox:
     ```bash
     mise run sandbox:stop
     ```
  3. On Windows, check what process owns port 8080:
     ```powershell
     Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue
     ```

### Symptom: `cgroup is not mounted. Memory limited without swap.`
* **Note:** This is an informational warning emitted by WSL2 when swap limits are not configured in the guest kernel. The container memory limit (`--memory 48G`) remains active and enforced.

---

## 3. Healthcheck & Loading Delays

### Model Load Timing
Flint NVFP4 consists of **21.21 GiB** of model weights across 50 layers. 
- On first launch, reading the weights from disk and allocating GPU tensor buffers into `CUDA0` typically takes **60 to 85 seconds**.
- The `sandbox:wait` task uses a default 120-second timeout. If your storage drive is slow or busy, you can increase the timeout:
  ```powershell
  powershell -File scripts/wait-healthy.ps1 -TimeoutSeconds 180
  ```

### Viewing Real-Time Initialization Logs
If `sandbox:wait` is taking longer than expected, tail the container logs to inspect progress:
```bash
mise run sandbox:logs
# Or live follow:
wslc logs -f flint-nvfp4
```
Healthy initialization will display:
```text
I load_tensors: offloaded 50/50 layers to GPU
I load_tensors: CUDA0 model buffer size = 21212.21 MiB
I srv server_on_li: listening on http://0.0.0.0:8080
```

---

## 4. Authentication Failures

### Symptom: `HTTP Error 401: Unauthorized`
* **Cause:** `llama-server` is started with `--api-key <KEY>`. All requests must present a matching Bearer token in the `Authorization` header.
* **Fix:**
  1. Check that `FLINT_API_KEY` is defined in your `.env`:
     ```dotenv
     FLINT_API_KEY=your-secure-local-api-key-here
     ```
  2. When calling curl, supply the header:
     ```bash
     curl -H "Authorization: Bearer your-secure-local-api-key-here" http://127.0.0.1:8080/v1/models
     ```
  3. In `omp` configuration (`~/.omp/agent/models.yml`), verify that `apiKey` is set and `auth: none` is **not** present.

---

## 5. WSL2 NAT Loopback Behavior

### Symptom: `curl http://127.0.0.1:8080` from inside WSL fails with `Connection refused`
* **Cause:** By default, WSL2 uses NAT virtual networking. When `wslc` publishes a port with `-p 127.0.0.1:8080:8080`, it publishes to the **Windows host's loopback interface**, not the guest Linux VM's loopback interface.
* **Fix:**
  - **Option A (Recommended - Tailnet):** Use the Tailscale MagicDNS endpoint (`https://<node-name>.<tailnet-name>.ts.net/v1`). Tailscale routes packets across network namespaces with full TLS encryption.
  - **Option B (PowerShell Interop):** Use `powershell.exe` to execute scripts or curl from the Windows host namespace (as `mise` tasks do via `scripts/smoke-test.ps1`).

---

## 6. Live Telemetry & Inspection Commands

### Check Container Resource Stats
```bash
wslc stats flint-nvfp4
```

### Inspect Processes & Filesystem Inside Container
```bash
wslc exec -it flint-nvfp4 /bin/bash
# Inside container:
ps aux
cat /proc/meminfo
ls -lh /models
```

### Monitor Physical Blackwell GPU Utilization
```bash
nvidia-smi -l 1
```

### Restart Container Cleanly
```bash
mise run sandbox:restart
```
