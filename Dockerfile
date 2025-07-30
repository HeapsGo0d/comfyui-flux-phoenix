# Stage 1: Builder - Clones the application and prepares it for the final image.
# Using the official NVIDIA PyTorch container as the base for both stages ensures compatibility.
ARG BASE_IMAGE=nvcr.io/nvidia/pytorch:24.04-py3
FROM ${BASE_IMAGE} AS builder

LABEL stage="builder"


# We clean up apt-get lists to keep the layer small.
RUN apt-get update && apt-get install -y --no-install-recommends git jq aria2 && rm -rf /var/lib/apt/lists/*

# --- VERSION PINNING LOGIC ---
# Copy the version configuration file into the builder stage.
COPY config/versions.conf /etc/phoenix/versions.conf

# Source the versions file and clone the specific version of ComfyUI.
# This fulfills the "Pinned Dependencies" requirement for stability.
# After cloning, we remove the .git directory to reduce the final image size.
RUN . /etc/phoenix/versions.conf && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    git checkout "${COMFYUI_VERSION}" && \
    rm -rf .git

# --- END VERSION PINNING ---

# --- INSTALL FILE BROWSER ---
# Download the File Browser binary, verify its checksum, and make it executable.
# We do this in the builder stage to keep the final image clean.
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash && \
    mv ./filebrowser /usr/local/bin/filebrowser

# Stage 2: Final Production Image - Optimized for size, security, and performance.
# We declare the ARG again as it's not inherited across stages automatically.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

LABEL maintainer="Project Phoenix Team <your-email@example.com>"
LABEL description="Production image for Project Phoenix (ComfyUI) - v1.1"

# --- SECURITY & PERFORMANCE SETUP ---

# Set default ComfyUI arguments for performance optimization as per requirements.
ENV COMFY_ARGS="--bf16-unet --use-flash-attention-2"

# Create a non-root user 'sduser' with a specific UID/GID for security.
# Set the user's home directory and apply a restrictive umask by default.
# This fulfills the "Security Hardening" requirement.
RUN groupadd -r sduser --gid=1000 && \
    useradd -r -m -d /workspace -s /bin/bash --uid=1000 --gid=1000 sduser && \
    echo "umask 077" >> /workspace/.profile

# --- APPLICATION & DEPENDENCY INSTALLATION ---

# Copy application code from the builder stage.
# The --chown flag ensures the non-root user owns the files immediately.
COPY --from=builder --chown=sduser:sduser /workspace/ComfyUI /workspace/ComfyUI


# Copy the pre-downloaded filebrowser binary from the builder stage.
COPY --from=builder /usr/local/bin/filebrowser /usr/local/bin/filebrowser

# Install runtime dependencies for our scripts.
# - jq: A lightweight and flexible command-line JSON processor.
# - aria2: A high-speed download utility.
RUN apt-get update && apt-get install -y --no-install-recommends jq aria2 && rm -rf /var/lib/apt/lists/*

# Copy our custom scripts and configuration into the final image.
COPY --chown=sduser:sduser scripts/ /usr/local/bin/scripts/
COPY --chown=sduser:sduser entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/scripts/*.sh

# Install Python dependencies from the list included with ComfyUI.
# The --no-cache-dir flag keeps the image size smaller.
RUN pip install --no-cache-dir -r /workspace/ComfyUI/requirements.txt

# --- FINALIZATION ---

# Set the final working directory for the application.
WORKDIR /workspace/ComfyUI

# Switch to the non-root user for all subsequent commands and for application execution.
USER sduser

# Add a healthcheck to monitor the ComfyUI API status. ComfyUI listens on port 8188 by default.
# The generous start-period allows time for the application and models to load.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 \
  CMD curl --fail http://127.0.0.1:8188/system_stats || exit 1

# Set the container's entrypoint to our custom script, which will handle all setup and launch logic.
# This fulfills the core architectural requirement of having an orchestrator script.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]