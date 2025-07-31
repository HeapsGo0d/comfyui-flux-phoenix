# ==============================================================================
# STAGE 1: BUILDER
# ==============================================================================
# This stage prepares all necessary components (application code, binaries)
# to be copied into a clean final image.

# Pinned to a specific monthly release for stability and reproducibility.
ARG BASE_IMAGE=nvcr.io/nvidia/pytorch:24.04-py3
FROM ${BASE_IMAGE} AS builder

LABEL stage="builder"

# Install build-time dependencies:
# - git: Required to clone the ComfyUI repository.
# - curl: Required to download the File Browser installation script.
# Set up DNS to prevent resolution issues in some environments
RUN echo "nameserver 8.8.8.8" > /etc/resolv.conf && echo "nameserver 1.1.1.1" >> /etc/resolv.conf

RUN apt-get update && apt-get install -y --no-install-recommends git curl && rm -rf /var/lib/apt/lists/*

# --- VERSION PINNING LOGIC ---
# Copy the version config and use it to check out a specific, stable version of ComfyUI.
COPY config/versions.conf /etc/phoenix/versions.conf
RUN . /etc/phoenix/versions.conf && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    git checkout "${COMFYUI_VERSION}" && \
    rm -rf .git

# --- INSTALL FILE BROWSER ---
# The official installer script downloads the binary and places it in /usr/local/bin automatically.
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash


# ==============================================================================
# STAGE 2: FINAL PRODUCTION IMAGE
# ==============================================================================
# This is the lean, secure, and optimized image that will be deployed.

# We declare the ARG again as it's not inherited across stages.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

LABEL maintainer="Project Phoenix Team <your-email@example.com>"
LABEL description="Production image for Project Phoenix (ComfyUI) - v1.3"

# --- SECURITY & PERFORMANCE SETUP ---
# Set default ComfyUI arguments for performance optimization.
ENV COMFY_ARGS="--bf16-unet"

# Create a non-root user 'sduser' and apply a restrictive umask by default.
RUN groupadd -r sduser --gid=1000 && \
    useradd -r -m -d /workspace -s /bin/bash --uid=1000 --gid=1000 sduser && \
    echo "umask 077" >> /workspace/.profile

# --- APPLICATION & DEPENDENCY INSTALLATION ---

# Copy the prepared application code from the builder stage.
COPY --from=builder --chown=sduser:sduser /workspace/ComfyUI /workspace/ComfyUI

# Copy the pre-downloaded File Browser binary from the builder stage.
COPY --from=builder /usr/local/bin/filebrowser /usr/local/bin/filebrowser

# Install runtime dependencies for our scripts:
# - jq: A command-line JSON processor for the Civitai API.
# - aria2: A high-speed download utility.
RUN apt-get update && apt-get install -y --no-install-recommends jq aria2 && rm -rf /var/lib/apt/lists/*

# Copy our custom scripts into the final image and make them executable.
COPY --chown=sduser:sduser scripts/ /usr/local/bin/scripts/
COPY --chown=sduser:sduser entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/scripts/*.sh && chmod +x /usr/local/bin/scripts/*.py

# Install Python dependencies from the list included with ComfyUI.
RUN pip install --no-cache-dir -r /workspace/ComfyUI/requirements.txt
RUN pip install --no-cache-dir requests

# --- FINALIZATION ---
# Set the final working directory for the application.
WORKDIR /workspace/ComfyUI

# Switch to the non-root user for all subsequent commands.
USER sduser

# Add a healthcheck to monitor the ComfyUI API status.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 \
  CMD curl --fail http://127.0.0.1:8188/system_stats || exit 1

# Set the container's entrypoint to our custom orchestrator script.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]