# Stage 1: Builder using pinned CentOS Stream 10 (Fedora/RHEL ecosystem) + NVIDIA CUDA 13.5 sbsa
FROM quay.io/centos/centos@sha256:511d358446140e9c4ba16451affb103a14237cbf40059b18adeaef6e3080a72b AS builder

ARG LLAMA_VER=b12186
ARG LLAMA_SHA256=2f6b2d904857e799f9e5488d7887c2eb760f3ef64039d6c3102935f7ebbd1426

# Install build dependencies and NVIDIA CUDA 13.5 Linux aarch64 toolchain
RUN curl -fsSL -o /etc/yum.repos.d/cuda-rhel10.repo \
    https://developer.download.nvidia.com/compute/cuda/repos/rhel10/sbsa/cuda-rhel10.repo && \
    dnf install -y --nodocs \
    cmake gcc-c++ make tar \
    cuda-compiler-13-5 \
    cuda-cudart-devel-13-5 \
    cuda-driver-devel-13-5 \
    libcublas-devel-13-5 && \
    dnf clean all

WORKDIR /src

# Download and verify official llama.cpp source release tarball
RUN curl -fsSL -o llama.tar.gz \
    https://github.com/ggml-org/llama.cpp/archive/refs/tags/${LLAMA_VER}.tar.gz && \
    echo "${LLAMA_SHA256}  llama.tar.gz" | sha256sum -c - && \
    tar -xzf llama.tar.gz --strip-components=1 && \
    rm llama.tar.gz

# Compile targeting Blackwell SM 12.1a (Blackwell RTX GPU with native FP4 acceleration)
WORKDIR /src/build
RUN cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="121a" \
    -DCMAKE_CUDA_COMPILER=/usr/local/cuda-13.5/bin/nvcc \
    -DLLAMA_CURL=OFF \
    -DCMAKE_INSTALL_PREFIX=/install && \
    cmake --build . --config Release -j$(nproc) --target llama-server

# Collect server binary, built ggml/llama shared libraries, and CUDA 13.5 runtime libraries
RUN mkdir -p /install/bin /install/lib && \
    cp -d /src/build/bin/llama-server /install/bin/ && \
    cp -d /src/build/bin/*.so* /install/lib/ && \
    cp -d /usr/local/cuda-13.5/targets/sbsa-linux/lib/libcudart.so* /install/lib/ && \
    cp -d /usr/local/cuda-13.5/targets/sbsa-linux/lib/libcublas.so* /install/lib/ && \
    cp -d /usr/local/cuda-13.5/targets/sbsa-linux/lib/libcublasLt.so* /install/lib/


# Stage 2: Runtime image using pinned Fedora 45 stable (aarch64)
FROM registry.fedoraproject.org/fedora@sha256:fd31d2f9dfd835cf7398af9cb6cbbbffbd33ffac2d5204042ea14157455b63a2

# Minimal runtime dependencies: GNU OpenMP, CA certificates, curl (for healthchecks)
RUN dnf install -y --setopt=install_weak_deps=False \
    libgomp ca-certificates curl && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

WORKDIR /app

# Copy built server executable and all required shared libraries
COPY --from=builder /install/bin/llama-server /app/llama-server
COPY --from=builder /install/lib/ /app/

# Configure library loader paths (WSL CUDA UMD + container app directory)
ENV PATH="/app:$PATH"
ENV LD_LIBRARY_PATH="/usr/lib/wsl/lib:/app:$LD_LIBRARY_PATH"

# Hive Commons Sandbox Standard: Unprivileged user execution (UID:GID 1000:1000)
RUN useradd -u 1000 -m -s /bin/bash sandbox && \
    chown -R 1000:1000 /app

USER 1000:1000

EXPOSE 8080
ENTRYPOINT ["llama-server"]
