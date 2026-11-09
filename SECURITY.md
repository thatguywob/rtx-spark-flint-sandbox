# Security Policy

The **RTX Spark Flint Sandbox** project is designed from the ground up around defense-in-depth isolation and credential-free execution, following CNCF cloud-native container standards and the [Hive Commons Sandbox Isolation Policy](https://github.com/hivecommons/hive).

---

## 1. Reporting Security Vulnerabilities

We take the security of this project seriously. If you discover a potential vulnerability, please do **NOT** disclose it in a public issue, discussion, or pull request.

Instead, please report vulnerabilities through one of the following channels:

1. **GitHub Private Security Advisory (Preferred):**  
   Navigate to the repository's **Security** tab $\rightarrow$ **Advisories** $\rightarrow$ click **Report a vulnerability**.
2. **Private Security Contact:**  
   If GitHub Security Advisories are unavailable, contact the repository maintainers directly with details of the finding.

### What to Include in Your Report
- A detailed description of the vulnerability and its potential impact.
- Step-by-step reproduction instructions or a minimal proof-of-concept (PoC).
- Any specific configuration flags or environment settings required to trigger the issue.

### Response Timeline
- **Initial Acknowledgment:** Within 48 hours of receipt.
- **Triage & Status Update:** Within 5 business days.
- **Coordination & Fix:** We will collaborate on a validated patch and coordinate public disclosure once a fix is released.

---

## 2. Threat Model & Security Contract

This project treats the LLM inference server as an **untrusted code executor** running in a local workstation environment. Our isolation guarantees are structured across five defense-in-depth layers:

### A. MicroVM Hypervisor Boundary (Host vs. Guest)
Inference executes inside a WSL2 Linux utility virtual machine running on the Microsoft Hyper-V hypervisor. The hypervisor provides a hardware-enforced boundary separating the guest Linux environment and paravirtualized Direct3D GPU bridge (`/dev/dxg`) from the physical Windows NT host kernel.

### B. OCI Container Isolation (`wslc` / `runc`)
Inside the Linux guest, `wslc` isolates the container via Linux namespaces and cgroups:
* **Unprivileged User:** The server runs as user `sandbox` (`UID:GID 1000:1000`). Root privileges and `sudo` are stripped.
* **Read-Only Model Weights:** The target `.gguf` file is bind-mounted strictly read-only (`:ro`), preventing tampering or corruption of base model tensors.
* **Volatile Non-Executable Scratch:** Temporary scratch storage is confined to an in-memory `tmpfs` at `/tmp` (`size=1G,noexec,nosuid`). Execution of binaries dropped into `/tmp` is blocked by the kernel.
* **Memory Governance:** A cgroup limit of `--memory 48G` protects host system RAM from exhaustion during large prompt prefill operations.

### C. Ingress Isolation & Authentication Barrier
* **Loopback-Only Ingress:** Container port 8080 is published exclusively to the host loopback interface (`127.0.0.1:8080`). No listening sockets are opened to physical Wi-Fi or Ethernet LAN interfaces (`0.0.0.0`).
* **Mandatory Bearer Authorization:** Every incoming HTTP request must include `Authorization: Bearer <FLINT_API_KEY>`. Unauthenticated requests are rejected immediately with `HTTP 401 Unauthorized`, neutralizing browser cross-origin requests (CSRF) and local SSRF vectors.

### D. Binary Hardening & Egress Elimination
* `llama-server` is compiled from source with `-DLLAMA_CURL=OFF`, completely eliminating `libcurl` and outbound HTTP/HTTPS networking from the executable. The inference server cannot initiate outbound internet connections or exfiltrate prompts.
* *(Note: While the inference binary lacks network client code, the base Fedora container image retains standard utilities such as `curl` for container healthchecks. Full network namespace egress blocking can be enforced via host network policies if required).*

### E. Credential-Free Execution
The container environment receives zero host credentials, cloud tokens, GitHub access tokens, or SSH keys. The environment is strictly credential-free.

---

## 3. Remote Serving Best Practices (Tailscale / Private Mesh)

If serving Flint NVFP4 to other personal devices over a network:
- **Do NOT open physical ports (`0.0.0.0`) on your router or local LAN.**
- Use **Tailscale Serve** on the host to terminate TLS on a private MagicDNS endpoint (`https://<node-name>.<tailnet-name>.ts.net`) and reverse-proxy to loopback (`127.0.0.1:8080`).
- Ensure Tailnet node ACLs restrict access exclusively to your authenticated personal devices.
- Always retain a non-trivial secret in `FLINT_API_KEY`.
