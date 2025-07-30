#!/bin/bash
# ==================================================================================
# PHOENIX: FILE ORGANIZER SCRIPT (ENHANCED)
# ==================================================================================
# This script is sourced by entrypoint.sh. It intelligently moves files from the
# temporary download directory to their final destinations in the ComfyUI structure.

# --- Global Variables & Setup ---
readonly MODELS_DIR="${STORAGE_ROOT}/models"

# --- Logging Function ---
log_organizer() {
    echo "  [ORGANIZER] $1"
}

# --- Model Type Detection Function ---
detect_model_type() {
    local file="$1"
    local filename=$(basename "$file")
    local filesize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
    
    # Debug output
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        log_organizer "DEBUG: Analyzing file: $filename (${filesize} bytes)"
    fi
    
    # Convert filename to lowercase for matching
    local filename_lower="${filename,,}"
    
    # FLUX-specific detection (most specific first)
    case "$filename_lower" in
        *flux1-dev* | *flux.1-dev* | flux1-dev.safetensors)
            echo "flux_checkpoints"
            return
            ;;
        ae.safetensors)
            # FLUX VAE component
            echo "vae"
            return
            ;;
        model.safetensors)
            # Could be FLUX transformer - check size
            if [ "$filesize" -gt 20000000000 ]; then  # > 20GB likely FLUX transformer
                echo "flux_checkpoints"
            else
                echo "checkpoints"
            fi
            return
            ;;
        *diffusion_pytorch_model*.safetensors)
            # FLUX UNet components
            echo "flux_checkpoints"
            return
            ;;
    esac
    
    # Size-based heuristics (in bytes)
    if [ "$filesize" -gt 10000000000 ]; then  # > 10GB
        if [[ "$filename_lower" == *flux* ]]; then
            echo "flux_checkpoints"
        else
            echo "checkpoints"
        fi
        return
    fi
    
    # Pattern-based detection
    case "$filename_lower" in
        *lora* | *loha* | *locon*)
            echo "loras"
            ;;
        *vae*)
            echo "vae"
            ;;
        *controlnet* | *t2i-adapter* | *control_net*)
            echo "controlnet"
            ;;
        *upscale* | *esrgan* | *swinir* | *gfpgan* | *realesrgan*)
            echo "upscale_models"
            ;;
        *embedding* | *textual_inversion* | *ti_*)
            echo "embeddings"
            ;;
        *clip*)
            echo "clip"
            ;;
        *unet*)
            echo "unet"
            ;;
        *scheduler*)
            echo "schedulers"
            ;;
        *sdxl* | *sd1.5* | *sd_xl* | *checkpoint* | *ckpt*)
            echo "checkpoints"
            ;;
        *)
            # Default fallback based on file size
            if [ "$filesize" -gt 1000000000 ]; then  # > 1GB
                echo "checkpoints"
            else
                echo "loras"  # Smaller files are more likely LoRAs
            fi
            ;;
    esac
}

# --- Directory Creation Function ---
create_model_directories() {
    log_organizer "Creating model directory structure..."
    
    # Standard ComfyUI directories
    mkdir -p "${MODELS_DIR}/checkpoints"
    mkdir -p "${MODELS_DIR}/loras"
    mkdir -p "${MODELS_DIR}/vae"
    mkdir -p "${MODELS_DIR}/controlnet"
    mkdir -p "${MODELS_DIR}/upscale_models"
    mkdir -p "${MODELS_DIR}/embeddings"
    mkdir -p "${MODELS_DIR}/clip"
    mkdir -p "${MODELS_DIR}/unet"
    mkdir -p "${MODELS_DIR}/schedulers"
    
    # FLUX-specific directories
    mkdir -p "${MODELS_DIR}/flux_checkpoints"
    
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        log_organizer "DEBUG: Created directory structure under ${MODELS_DIR}"
    fi
}

# --- File Processing Function ---
process_downloaded_files() {
    local total_files=0
    local processed_files=0
    local skipped_files=0
    
    # Count total files first
    if [ -d "${DOWNLOAD_TMP_DIR}" ]; then
        total_files=$(find "${DOWNLOAD_TMP_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) | wc -l)
        log_organizer "Found ${total_files} model files to process"
    fi
    
    if [ "$total_files" -eq 0 ]; then
        log_organizer "No model files found to organize"
        return
    fi
    
    # Process each file
    find "${DOWNLOAD_TMP_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) -print0 | while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        local model_type=$(detect_model_type "$file")
        local destination_dir="${MODELS_DIR}/${model_type}"
        
        # Progress indicator
        processed_files=$((processed_files + 1))
        log_organizer "Processing (${processed_files}/${total_files}): ${filename}"
        
        # Ensure destination directory exists
        mkdir -p "${destination_dir}"
        
        # Check if file already exists in destination
        if [ -f "${destination_dir}/${filename}" ]; then
            log_organizer "ℹ️ File '${filename}' already exists in ${model_type}. Skipping."
            skipped_files=$((skipped_files + 1))
            continue
        fi
        
        # Move the file
        if [ "${DEBUG_MODE:-false}" = "true" ]; then
            log_organizer "DEBUG: Moving '${filename}' to '${destination_dir}' (detected as: ${model_type})"
        else
            log_organizer "Moving '${filename}' to '${model_type}'"
        fi
        
        if mv "$file" "${destination_dir}/"; then
            log_organizer "✅ Successfully moved ${filename}"
        else
            log_organizer "❌ Failed to move ${filename}"
        fi
    done
    
    log_organizer "File processing complete. Processed: ${processed_files}, Skipped: ${skipped_files}"
}

# --- Directory Structure Display ---
show_final_structure() {
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        log_organizer "DEBUG: Final model directory structure:"
        find "${MODELS_DIR}" -type f -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" | while read -r file; do
            local rel_path=${file#${MODELS_DIR}/}
            log_organizer "  📁 ${rel_path}"
        done
    fi
}

# --- Main Organizing Logic ---
organize_files() {
    log_organizer "Starting file organization process..."
    
    # Validate environment
    if [ -z "${STORAGE_ROOT:-}" ]; then
        log_organizer "❌ ERROR: STORAGE_ROOT not set. System setup may have failed."
        exit 1
    fi
    
    if [ -z "${DOWNLOAD_TMP_DIR:-}" ]; then
        log_organizer "❌ ERROR: DOWNLOAD_TMP_DIR not set. System setup may have failed."
        exit 1
    fi
    
    # Check if download directory exists and has content
    if [ ! -d "${DOWNLOAD_TMP_DIR}" ] || [ -z "$(ls -A "${DOWNLOAD_TMP_DIR}" 2>/dev/null)" ]; then
        log_organizer "No files found in download directory (${DOWNLOAD_TMP_DIR}). Skipping organization."
        return
    fi
    
    # Create directory structure
    create_model_directories
    
    # Process all downloaded files
    process_downloaded_files
    
    # Show final structure in debug mode
    show_final_structure
    
    # Cleanup temp directory
    log_organizer "Cleaning up temporary download directory..."
    rm -rf "${DOWNLOAD_TMP_DIR}"
    
    log_organizer "✅ Organization complete."
}

# Execute the main function
organize_files