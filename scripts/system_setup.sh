#!/bin/bash
# shellcheck disable=SC2034 # Disable warnings for unused variables, as this script is sourced.

# ==================================================================================
# PHOENIX: ROBUST SYSTEM SETUP SCRIPT
# ==================================================================================
# This script ensures directory structure is always created, even after cleanup cycles

# --- Security Setup ---
set -euo pipefail
umask 077

# --- Global Variables ---
readonly COMFYUI_DIR="/workspace/ComfyUI"

# --- Logging Function ---
log_system() {
    echo "  [SYSTEM] $1"
}

log_system "Initializing system checks..."

# --- Storage Detection with Fallback Protection ---
detect_storage_root() {
    if [ "${USE_VOLUME:-false}" = "true" ] && [ -d "/runpod-volume" ]; then
        log_system "✅ Persistent storage detected at /runpod-volume."
        export STORAGE_ROOT="/runpod-volume"
    else
        log_system "ℹ️ Using ephemeral storage at /workspace."
        export STORAGE_ROOT="/workspace"
    fi
    
    log_system "Storage root set to: ${STORAGE_ROOT}"
}

# --- Critical Directory Structure Creation ---
create_essential_directories() {
    log_system "Creating essential directory structure..."
    
    # Core ComfyUI directories that MUST exist
    local essential_dirs=(
        "${STORAGE_ROOT}/models"
        "${STORAGE_ROOT}/models/checkpoints"
        "${STORAGE_ROOT}/models/flux_checkpoints"
        "${STORAGE_ROOT}/models/loras"
        "${STORAGE_ROOT}/models/vae"
        "${STORAGE_ROOT}/models/controlnet"
        "${STORAGE_ROOT}/models/upscale_models"
        "${STORAGE_ROOT}/models/embeddings"
        "${STORAGE_ROOT}/models/clip"
        "${STORAGE_ROOT}/models/unet"
        "${STORAGE_ROOT}/input"
        "${STORAGE_ROOT}/output"
        "${STORAGE_ROOT}/temp"
    )
    
    for dir in "${essential_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            chmod 755 "$dir"  # Slightly less restrictive for ComfyUI access
            log_system "Created: $dir"
        fi
    done
    
    # Export download temp directory
    export DOWNLOAD_TMP_DIR="/workspace/downloads_tmp"
    mkdir -p "${DOWNLOAD_TMP_DIR}"
    chmod 700 "${DOWNLOAD_TMP_DIR}"
    
    log_system "✅ Essential directories verified/created"
}

# --- GPU Detection (Non-Fatal) ---
detect_gpu() {
    if command -v nvidia-smi &> /dev/null; then
        log_system "✅ NVIDIA GPU detected. Details:"
        nvidia-smi --query-gpu=gpu_name,driver_version,memory.total --format=csv,noheader,nounits | while IFS=, read -r name driver memory; do
            log_system "  - Name: ${name}, Driver: ${driver}, VRAM: ${memory}MiB"
        done
        
        export GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader,nounits | head -n1)
        export GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
        export GPU_AVAILABLE=true
    else
        log_system "⚠️ WARNING: No NVIDIA GPU detected. ComfyUI may run in CPU mode."
        export GPU_NAME="CPU_MODE"
        export GPU_MEMORY="0"
        export GPU_AVAILABLE=false
    fi
}

# --- ComfyUI Directory Validation (Non-Fatal) ---
validate_comfyui() {
    log_system "Validating ComfyUI installation..."
    
    if [ ! -d "${COMFYUI_DIR}" ]; then
        log_system "❌ ERROR: ComfyUI directory not found at ${COMFYUI_DIR}"
        log_system "   This is a critical error - the Docker image may be corrupted."
        return 1
    fi
    
    # Check for essential ComfyUI files
    local essential_files=(
        "${COMFYUI_DIR}/main.py"
        "${COMFYUI_DIR}/nodes.py"
    )
    
    for file in "${essential_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_system "⚠️ WARNING: Missing ComfyUI file: $file"
        fi
    done
    
    # Ensure ComfyUI has basic directory structure
    local comfyui_dirs=(
        "${COMFYUI_DIR}/custom_nodes"
        "${COMFYUI_DIR}/web"
    )
    
    for dir in "${comfyui_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_system "⚠️ WARNING: Missing ComfyUI directory: $dir"
            mkdir -p "$dir" || true
        fi
    done
    
    log_system "✅ ComfyUI validation complete"
    return 0
}

# --- Environment Validation ---
validate_environment() {
    log_system "Validating environment configuration..."
    
    # Check for required tools
    local required_tools=("curl" "aria2c" "jq")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_system "❌ ERROR: Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    # Check disk space
    local available_gb=$(df -BG "${STORAGE_ROOT}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_gb" -lt 5 ]; then
        log_system "⚠️ WARNING: Low disk space (${available_gb}GB available)"
        log_system "   FLUX models require significant storage space"
    else
        log_system "✅ Adequate disk space: ${available_gb}GB available"
    fi
    
    return 0
}

# --- Debug Information ---
show_debug_info() {
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        log_system "DEBUG: System configuration:"
        log_system "  STORAGE_ROOT=${STORAGE_ROOT}"
        log_system "  DOWNLOAD_TMP_DIR=${DOWNLOAD_TMP_DIR}"
        log_system "  GPU_NAME=${GPU_NAME:-unknown}"
        log_system "  GPU_MEMORY=${GPU_MEMORY:-0}MiB"
        log_system "  GPU_AVAILABLE=${GPU_AVAILABLE:-false}"
        log_system "  USE_VOLUME=${USE_VOLUME:-false}"
        log_system "  PARANOID_MODE=${PARANOID_MODE:-false}"
        
        log_system "DEBUG: Directory structure:"
        find "${STORAGE_ROOT}" -type d -maxdepth 3 2>/dev/null | sort | while read -r dir; do
            log_system "  📁 ${dir}"
        done
    fi
}

# --- Main Setup Function ---
main_setup() {
    local setup_errors=0
    
    # Step 1: Storage detection (always succeeds)
    detect_storage_root
    
    # Step 2: Create directory structure (critical - must succeed)
    if ! create_essential_directories; then
        log_system "❌ FATAL: Could not create essential directories"
        exit 1
    fi
    
    # Step 3: Environment validation (critical - must succeed)
    if ! validate_environment; then
        log_system "❌ FATAL: Environment validation failed"
        exit 1
    fi
    
    # Step 4: GPU detection (non-fatal)
    detect_gpu || setup_errors=$((setup_errors + 1))
    
    # Step 5: ComfyUI validation (non-fatal but important)
    if ! validate_comfyui; then
        log_system "⚠️ ComfyUI validation failed - some features may not work"
        setup_errors=$((setup_errors + 1))
    fi
    
    # Step 6: Debug information
    show_debug_info
    
    # Summary
    if [ $setup_errors -eq 0 ]; then
        log_system "✅ System setup complete - all checks passed"
    else
        log_system "⚠️ System setup complete with ${setup_errors} warnings"
        log_system "   Container will continue but some features may be limited"
    fi
    
    return 0
}

# Execute main setup
main_setup