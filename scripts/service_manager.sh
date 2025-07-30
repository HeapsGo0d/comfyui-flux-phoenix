#!/bin/bash
# ==================================================================================
# PHOENIX: SERVICE MANAGER SCRIPT
# ==================================================================================
# This script is sourced by entrypoint.sh. It is responsible for launching the
# main application services (ComfyUI, File Browser) in the background.

# --- Logging Function ---
log_service() {
    echo "  [SERVICE] $1"
}

# --- Storage Linking ---
# This is a critical step to ensure ComfyUI can access the models, inputs,
# and outputs regardless of whether we are using persistent or ephemeral storage.
# We will replace the default ComfyUI directories with symlinks to our STORAGE_ROOT.
setup_storage_links() {
    log_service "Setting up storage links..."

    # Ensure the target directories exist in our storage root.
    mkdir -p "${STORAGE_ROOT}/models" "${STORAGE_ROOT}/input" "${STORAGE_ROOT}/output"

    # Forcefully create symlinks. This will overwrite existing directories or symlinks.
    # The -n flag is important to handle cases where the target is already a symlink.
    ln -sfn "${STORAGE_ROOT}/models" "${COMFYUI_DIR}/models"
    ln -sfn "${STORAGE_ROOT}/input" "${COMFYUI_DIR}/input"
    ln -sfn "${STORAGE_ROOT}/output" "${COMFYUI_DIR}/output"

    log_service "✅ Storage links configured to point to ${STORAGE_ROOT}"
}

# --- File Browser Launcher ---
launch_file_browser() {
    log_service "Launching File Browser..."

    local username="${FB_USERNAME:-admin}"
    local password="${FB_PASSWORD:-}"
    local db_path="${STORAGE_ROOT}/filebrowser.db"

    # If no password is provided, generate a random 16-character one.
    if [ -z "$password" ]; then
        password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
        log_service "---------------------------------------------------"
        log_service "Generated File Browser Password: ${password}"
        log_service "---------------------------------------------------"
    fi

    # Initialize the database and user if the DB file doesn't exist.
    if [ ! -f "$db_path" ]; then
        log_service "Initializing new File Browser database at ${db_path}"
        filebrowser config init --database "$db_path"
        filebrowser users add "$username" "$password" --database "$db_path" --perm.admin
    fi

    # Launch File Browser in the background, serving the entire /workspace directory.
    # We pipe its output to a logger to prepend a tag for clarity.
    filebrowser --database "$db_path" \
        --address 0.0.0.0 \
        --port 8080 \
        --root /workspace | while read -r line; do echo "  [FileBrowser] $line"; done &
    
    log_service "✅ File Browser is starting up on port 8080."
}

# --- ComfyUI Launcher ---
launch_comfyui() {
    log_service "Launching ComfyUI..."
    cd "${COMFYUI_DIR}"

    # Construct the final arguments for ComfyUI.
    # The COMFY_ARGS env var is set in the Dockerfile.
    local launch_args="--listen 0.0.0.0 --port 8188 ${COMFY_ARGS}"
    log_service "ComfyUI launch arguments: ${launch_args}"

    # Launch ComfyUI in the background.
    # stdbuf -o0 ensures that Python's output is not buffered, so we see logs immediately.
    stdbuf -o0 python main.py ${launch_args} | while read -r line; do echo "  [ComfyUI] $line"; done &
    
    log_service "✅ ComfyUI is starting up on port 8188."
}

# --- Main Orchestration ---
log_service "Initializing service manager..."
setup_storage_links
launch_file_browser
launch_comfyui
log_service "All services launched."
