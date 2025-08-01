#!/bin/bash
# ==================================================================================
# PHOENIX: ENHANCED SERVICE MANAGER SCRIPT
# ==================================================================================
# Enhanced version that ensures FileBrowser sees all models after organization

# --- Logging Function ---
log_service() {
    echo "  [SERVICE] $1"
}

# --- Storage Linking (Enhanced) ---
setup_storage_links() {
    log_service "Setting up storage links..."

    # Ensure ALL ComfyUI model subdirectories exist
    local model_dirs=(
        "checkpoints" "loras" "vae" "controlnet" 
        "upscale_models" "embeddings" "clip" "unet"
        "diffusion_models" "style_models"
    )
    
    for dir in "${model_dirs[@]}"; do
        mkdir -p "${STORAGE_ROOT}/models/${dir}"
    done
    
    # Also ensure input/output dirs exist
    mkdir -p "${STORAGE_ROOT}/input" "${STORAGE_ROOT}/output"

    # Create symlinks (force overwrite existing)
    ln -sfn "${STORAGE_ROOT}/models" "${COMFYUI_DIR}/models"
    ln -sfn "${STORAGE_ROOT}/input" "${COMFYUI_DIR}/input"
    ln -sfn "${STORAGE_ROOT}/output" "${COMFYUI_DIR}/output"

    log_service "✅ Storage links configured to point to ${STORAGE_ROOT}"
    log_service "   Model structure: $(find ${STORAGE_ROOT}/models -type d | wc -l) directories ready"
}

# --- Wait for Downloads to Complete ---
wait_for_downloads() {
    log_service "Checking for ongoing downloads..."
    local max_wait=300  # 5 minutes max wait
    local elapsed=0
    local check_interval=5
    
    while [ $elapsed -lt $max_wait ]; do
        # Check for aria2 segment files (indicates active downloads)
        local aria_files
        aria_files=$(find "${DOWNLOAD_TMP_DIR:-/workspace/downloads_tmp}" -name "*.aria2" 2>/dev/null | wc -l)
        
        # Check for python download processes
        local hf_processes
        hf_processes=$(pgrep -f "huggingface-cli download" | wc -l)
        
        if [ "$aria_files" -eq 0 ] && [ "$hf_processes" -eq 0 ]; then
            log_service "✅ All downloads appear complete"
            return 0
        fi
        
        log_service "⏳ Downloads still active (aria2: $aria_files, hf: $hf_processes) - waiting..."
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    log_service "⚠️  Download wait timeout reached - proceeding anyway"
    return 0
}

# --- Enhanced File Browser Launcher ---
launch_file_browser() {
    log_service "Preparing File Browser launch..."

    local username="${FB_USERNAME:-admin}"
    local password="${FB_PASSWORD:-}"
    local db_path="${STORAGE_ROOT}/filebrowser.db"

    # Generate password if needed
    if [ -z "$password" ]; then
        password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
        log_service "---------------------------------------------------"
        log_service "Generated File Browser Password: ${password}"
        log_service "---------------------------------------------------"
    fi

    # Initialize database if needed
    if [ ! -f "$db_path" ]; then
        log_service "Initializing new File Browser database at ${db_path}"
        filebrowser config init --database "$db_path"
        filebrowser users add "$username" "$password" --database "$db_path" --perm.admin
        
        # Configure File Browser settings for better model visibility
        filebrowser config set --database "$db_path" \
            --branding.name "Phoenix Models" \
            --branding.files "/workspace" \
            --commands.after-upload "" \
            --commands.before-save ""
    fi

    # Wait a moment for file system to settle
    log_service "Waiting for file system to settle..."
    sleep 3

    ### DEBUG: filebrowser_debug.sh START
    debug_filebrowser_setup() {
        if [ "${DEBUG_MODE:-false}" = "true" ]; then
            echo "  [SERVICE-DEBUG] === FILEBROWSER SETUP DEBUG ==="
            echo "  [SERVICE-DEBUG] FileBrowser root will be: /workspace"
            echo "  [SERVICE-DEBUG] /workspace contents:"
            ls -la /workspace/ | while read -r line; do
                echo "  [SERVICE-DEBUG]   $line"
            done
            
            echo "  [SERVICE-DEBUG] /workspace/models contents:"
            if [ -d "/workspace/models" ]; then
                find /workspace/models -type f | head -20 | while read -r file; do
                    echo "  [SERVICE-DEBUG]   $(ls -la "$file")"
                done
            else
                echo "  [SERVICE-DEBUG]   /workspace/models does not exist!"
            fi
            
            echo "  [SERVICE-DEBUG] Current user: $(whoami)"
            echo "  [SERVICE-DEBUG] Current groups: $(groups)"
            echo "  [SERVICE-DEBUG] umask: $(umask)"
            echo "  [SERVICE-DEBUG] === END FILEBROWSER DEBUG ==="
        fi
    }

    # Call debug function before launch
    debug_filebrowser_setup
    ### DEBUG: filebrowser_debug.sh END

    # Launch File Browser with optimized settings
    log_service "Launching File Browser on port 8080..."
    filebrowser --database "$db_path" \
        --address 0.0.0.0 \
        --port 8080 \
        --root /workspace \
        --cache-dir "${STORAGE_ROOT}/.fb_cache" | while read -r line; do 
            echo "  [FileBrowser] $line"
        done &
    
    # Store the PID for potential restarts
    echo $! > "${STORAGE_ROOT}/.filebrowser.pid"
    
    log_service "✅ File Browser started (PID: $(cat ${STORAGE_ROOT}/.filebrowser.pid))"
}

# --- File Browser Restart Function ---
restart_file_browser() {
    log_service "Restarting File Browser to refresh model view..."
    
    if [ -f "${STORAGE_ROOT}/.filebrowser.pid" ]; then
        local fb_pid
        fb_pid=$(cat "${STORAGE_ROOT}/.filebrowser.pid")
        if kill -0 "$fb_pid" 2>/dev/null; then
            kill "$fb_pid"
            sleep 2
        fi
    fi
    
    launch_file_browser
}

# --- ComfyUI Launcher (Enhanced) ---
launch_comfyui() {
    log_service "Launching ComfyUI..."
    cd "${COMFYUI_DIR}"

    # Enhanced launch arguments
    local launch_args="--listen 0.0.0.0 --port 8188 ${COMFY_ARGS}"
    
    # Add model scanning args if models exist
    if [ -d "${STORAGE_ROOT}/models" ] && [ "$(find ${STORAGE_ROOT}/models -name '*.safetensors' -o -name '*.ckpt' | head -1)" ]; then
        launch_args="$launch_args --extra-model-paths-config /dev/null"
        log_service "Models detected - ComfyUI will scan: $(find ${STORAGE_ROOT}/models -name '*.safetensors' -o -name '*.ckpt' | wc -l) files"
    fi

    log_service "ComfyUI launch arguments: ${launch_args}"

    # Launch with unbuffered output
    stdbuf -o0 python main.py ${launch_args} | while read -r line; do 
        echo "  [ComfyUI] $line"
    done &
    
    log_service "✅ ComfyUI starting on port 8188"
}

# --- Model Monitoring Background Task ---
start_model_monitor() {
    {
        log_service "Starting background model monitor..."
        local last_count=0
        
        while true; do
            sleep 30
            
            if [ -d "${STORAGE_ROOT}/models" ]; then
                local current_count
                current_count=$(find "${STORAGE_ROOT}/models" -name '*.safetensors' -o -name '*.ckpt' | wc -l)
                
                if [ "$current_count" -ne "$last_count" ]; then
                    log_service "📁 Model count changed: $last_count → $current_count"
                    
                    # Restart FileBrowser to refresh its view
                    if [ "$current_count" -gt "$last_count" ]; then
                        log_service "New models detected - refreshing FileBrowser..."
                        restart_file_browser
                    fi
                    
                    last_count=$current_count
                fi
            fi
        done
    } &
}

# --- Main Orchestration (Enhanced) ---
log_service "Initializing enhanced service manager..."

# Step 1: Set up storage structure
setup_storage_links

# Step 2: Wait for any ongoing downloads to complete
wait_for_downloads

# Step 3: Wait a bit more for organizer to finish moving files
log_service "Allowing time for file organization to complete..."
sleep 5

# Step 4: Launch services with proper timing
launch_comfyui
sleep 3  # Let ComfyUI start first

launch_file_browser
sleep 2

# Step 5: Start background monitor
start_model_monitor

log_service "🚀 All services launched with enhanced model visibility"
log_service "   - ComfyUI: http://localhost:8188"
log_service "   - FileBrowser: http://localhost:8080"
log_service "   - Background monitor: Active"