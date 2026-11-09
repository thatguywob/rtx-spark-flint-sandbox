# Architecture & Security Specification

This document provides a technical deep dive into the sandboxed serving architecture for **Flint NVFP4** (`RecursiveSI/flint-nvfp4-gguf`), covering hardware paravirtualization, microVM isolation, container sandboxing, multi-threading, and zero-trust ingress.

---

## 1. System Topology

```
┌────────────────────────────────────────────────────────────────────────┐
│ Physical Windows 11 ARM64 Host                                         │
│                                                                        │
│   • NVIDIA RTX Spark N1X GPU (6144-core Blackwell, SM 12.1a)           │
│   • 101.4 GiB Unified System Memory (shared CPU / GPU DRAM)            │
│   • NVIDIA Display Driver 621.14 (Kernel Mode Driver)                  │
│   • Tailscale Serve Reverse Proxy (TLS 1.3 Termination)                │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
    ┌───────────────────────────────▼────────────────────────────────┐
    │ Hyper-V Hypervisor Boundary (WSL2 Utility VM)                  │
    │                                                                │
    │   /dev/dxg (Direct3D / CUDA UMD Paravirtualization Bridge)     │
    │      │                                                         │
    │   ┌──▼──────────────────────────────────────────────────────┐  │
    │   │ Sandboxed Fedora 45 OCI Container (runc / wslc)         │  │
    │   │                                                         │  │
    │   │  • Unprivileged non-root user (UID:GID 1000:1000)       │  │
    │   │  • Read-only model mount (:ro, 21.21 GiB VRAM buffer)   │  │
    │   │  • Volatile scratch (/tmp tmpfs 1G, noexec, nosuid)     │  │
    │   │  • Egress eliminated (-DLLAMA_CURL=OFF)                 │  │
    │   │  • 20 OpenMP CPU worker threads (libgomp.so.1)          │  │
    │   │  • 50/50 layers offloaded to CUDA0 (native SM 12.1a)    │  │
    │   │  • Ingress: Loopback-only (127.0.0.1:8080)              │  │
    │   └─────────────────────────────────────────────────────────┘  │
    └────────────────────────────────────────────────────────────────┘
```

---

## 2. Hardware Paravirtualization Layer

### Unified Memory Architecture
The NVIDIA RTX Spark N1X architecture operates with unified physical DRAM (101.4 GiB total capacity). System RAM and GPU VRAM share the same physical memory bus, allowing zero-copy tensor passing between the CPU and GPU.

### Zero Linux Driver Overhead (`/dev/dxg`)
Rather than running a monolithic Linux display driver inside WSL2, Microsoft's DirectX Graphics Kernel subsystem (`/dev/dxg`) paravirtualizes GPU operations directly to the Windows Kernel Mode Driver (KMD). 

Inside the container:
- `/usr/lib/wsl/lib` is mounted dynamically when passing `--gpus all`.
- `llama-server` links against the extracted SBSA CUDA 13.5 runtime (`libcudart.so.13`, `libcublas.so.13`) and dynamically binds to the host's `/usr/lib/wsl/lib/libcuda.so.1` (the CUDA User-Mode Driver).
- All 50 model layers (21.21 GiB) offload directly to `CUDA0` without emulation overhead.

---

## 3. MicroVM & Container Sandboxing

Isolation follows defense-in-depth principles aligned with CNCF container isolation and Hive Commons Sandbox Isolation policies:

### Hypervisor MicroVM Boundary
WSL2 runs inside a Hyper-V Linux utility virtual machine. A process running inside the container cannot directly interact with the Windows NT kernel; any escape or kernel vulnerability is constrained within the virtualized Linux environment.

### OCI Sandboxing (`wslc`)
Inside WSL2, `wslc` manages the container runtime via `runc` and Linux namespaces:
1. **Unprivileged Execution:** The container runs as user `sandbox` (`UID:GID 1000:1000`). Root privileges and `sudo` are stripped.
2. **Read-Only Model Weights:** The `.gguf` file is mounted `:ro`. The inference process cannot alter, overwrite, or corrupt the base model weights.
3. **Filesystem Permissions & Scratch:** Writable temporary storage is mounted as an in-memory `tmpfs` at `/tmp` (`size=1G,noexec,nosuid`), where binary execution is blocked by the kernel. Model weights are mounted strictly read-only (`:ro`). The rootfs `/` is root-owned, while the application working directory `/app` is owned by the unprivileged user `sandbox` (UID 1000).
4. **Memory Governance:** A cgroup ceiling of `--memory 48G` bounds host memory allocations inside WSL2 during context processing.

---

## 4. Multi-Threading & Compute Architecture

### OpenMP CPU Concurrency (`libgomp.so.1`)
Inference is not purely GPU-bound; prompt batching, BPE tokenization, and tensor reductions require high-throughput CPU processing.
- The container dynamically links to Fedora 45's GNU OpenMP library (`/lib64/libgomp.so.1`).
- `llama-server` is configured with 20 parallel threads (`n_threads = 20`, `n_threads_batch = 20`) matching the physical ARM64 CPU core count.

### Blackwell Native FP4 Acceleration
Compilation flags enforce target architecture `121a` (`-DCMAKE_CUDA_ARCHITECTURES="121a"`). This enables hardware-accelerated NVFP4 tensor core instructions on Blackwell, achieving sustained decode speeds exceeding **70 tokens/second** with **0.31s TTFT** (time-to-first-token) on a 39.8B parameter model.

---

## 5. Network & Zero-Trust Ingress

```
Remote Client ──[Tailnet WireGuard / TLS 1.3]──► Tailscale Serve (Port 443)
                                                        │
                                                        ▼
Local Client ──[Loopback HTTP + Bearer Token]──► 127.0.0.1:8080 (WSL Ingress)
                                                        │
                                                        ▼
                                                 llama-server (Container)
```

1. **Loopback-Only Ingress:**  
   `wslc` binds the container port exclusively to host loopback (`127.0.0.1:8080`). No listening sockets are opened on physical Wi-Fi or Ethernet interfaces (`0.0.0.0`).
2. **Binary Egress Elimination:**  
   `llama-server` is compiled with `-DLLAMA_CURL=OFF`, completely removing `libcurl` and outbound HTTP/HTTPS networking from the executable. This is an application-level binary hardening measure; the base container image retains standard tools (such as `curl` used for healthchecks).
3. **Application Authentication Barrier:**  
   Every incoming HTTP request must include `Authorization: Bearer <FLINT_API_KEY>`. Unauthenticated probes are rejected immediately with `HTTP 401 Unauthorized`.
4. **Tailscale Serve Reverse Proxy:**  
   When serving over a private Tailnet, Tailscale terminates TLS on a private MagicDNS endpoint and forwards decrypted traffic to `127.0.0.1:8080`. Remote clients connect via encrypted HTTPS with mutual network authentication.
