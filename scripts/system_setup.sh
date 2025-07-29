#!/bin/bash
# shellcheck disable=SC2034 # Disable warnings for unused variables, as this script is sourced.

# ==================================================================================
# PHOENIX: SYSTEM SETUP SCRIPT
# ==================================================================================
# This script is sourced by entrypoint.sh. It performs initial environment
# validation, sets up global variables, and detects hardware.

# --- Global Variables ---
# Define readonly paths for ComfyUI and the storage root.
readonly COMFYUI_DIR="/workspace/ComfyUI"

# --- Logging Function ---
# A simple logging function to prepend "System Setup" to messages.
log_system() {
    echo "  [SYSTEM] $1"
}

log_system "Initializing system checks..."

# --- Storage Detection ---
# Check if a persistent volume is mounted at /runpod-volume.
# This determines where models, inputs, and outputs will be stored.
if [ -d "/runpod-volume" ]; then
    log_system "✅ Persistent storage detected at /runpod-volume."
    readonly STORAGE_ROOT="/runpod-volume"
    # Create necessary subdirectories in the persistent volume if they don't exist.
    mkdir -p "${STORAGE_ROOT}/models" "${STORAGE_ROOT}/inputs" "${STORAGE_ROOT}/outputs"
else
    log_system "ℹ️ No persistent storage detected. Using ephemeral /workspace."
    readonly STORAGE_ROOT="/workspace"
fi

log_system "Storage root set to: ${STORAGE_ROOT}"

# --- GPU Detection ---
# Check for NVIDIA GPU and log its information using nvidia-smi.
if command -v nvidia-smi &> /dev/null; then
    log_system "✅ NVIDIA GPU detected. Details:"
    # Indent the output of nvidia-smi for better readability.
    nvidia-smi --query-gpu=gpu_name,driver_version,memory.total --format=csv,noheader,nounits | while IFS=, read -r name driver memory; do
        log_system "  - Name: ${name}, Driver: ${driver}, VRAM: ${memory}MiB"
    done
else
    log_system "⚠️ WARNING: No NVIDIA GPU detected. Application may not run correctly."
fi

# --- Prerequisite Directory Checks ---
# Verify that the main ComfyUI directories exist.
log_system "Verifying prerequisite directories..."
if [ ! -d "${COMFYUI_DIR}/models" ] || [ ! -d "${COMFYUI_DIR}/custom_nodes" ]; then
    log_system "❌ ERROR: Core ComfyUI directories not found in ${COMFYUI_DIR}."
    log_system "   The Docker image may be corrupted. Exiting."
    exit 1
fi
log_system "✅ All prerequisite directories found."

log_system "System setup complete."
