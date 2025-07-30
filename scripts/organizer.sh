#!/bin/bash
# ==================================================================================
# PHOENIX: FILE ORGANIZER SCRIPT
# ==================================================================================
# This script is sourced by entrypoint.sh. It intelligently moves files from the
# temporary download directory to their final destinations in the ComfyUI structure.

# --- Global Variables & Setup ---
readonly DOWNLOAD_TMP_DIR="/workspace/downloads_tmp"
readonly MODELS_DIR="${STORAGE_ROOT}/models"

# --- Logging Function ---
log_organizer() {
    echo "  [ORGANIZER] $1"
}

# --- Main Organizing Logic ---
organize_files() {
    log_organizer "Starting file organization process..."

    # Check if the temporary download directory exists and is not empty.
    if [ ! -d "${DOWNLOAD_TMP_DIR}" ] || [ -z "$(ls -A "${DOWNLOAD_TMP_DIR}")" ]; then
        log_organizer "No files found in download directory. Skipping."
        return
    fi

    # Use 'find' to locate all relevant model files, handling spaces and special chars.
    # We are looking for the most common model file extensions.
    find "${DOWNLOAD_TMP_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" \) -print0 | while IFS= read -r -d '' file; do
        filename=$(basename "$file")
        destination_dir=""

        # --- Smart Categorization Logic ---
        # We use a case statement on the lowercase filename to determine the destination.
        case "${filename,,}" in
            *lora*|*loha*|*locon*)
                destination_dir="${MODELS_DIR}/loras"
                ;;
            *vae*)
                destination_dir="${MODELS_DIR}/vae"
                ;;
            *controlnet*|*t2i-adapter*)
                destination_dir="${MODELS_DIR}/controlnet"
                ;;
            *upscale*|*esrgan*|*swinir*|*gfpgan*)
                destination_dir="${MODELS_DIR}/upscale_models"
                ;;
            *embedding*|*textual_inversion*)
                destination_dir="${MODELS_DIR}/embeddings"
                ;;
            *sdxl*|*sd1.5*|*checkpoint*|*flux*)
                # This is a broad category for base models (checkpoints).
                destination_dir="${MODELS_DIR}/checkpoints"
                ;;
            *)
                # If no other category matches, we assume it's a base model.
                log_organizer "⚠️ Could not determine category for '${filename}'. Defaulting to Checkpoints."
                destination_dir="${MODELS_DIR}/checkpoints"
                ;;
        esac

        # Ensure the destination directory exists.
        mkdir -p "${destination_dir}"

        # --- Idempotency Check & Move ---
        if [ -f "${destination_dir}/${filename}" ]; then
            log_organizer "ℹ️ Skipping move for '${filename}', file already exists in destination."
        else
            log_organizer "Moving '${filename}' to '${destination_dir}'"
            mv "$file" "${destination_dir}/"
        fi
    done

    # --- Cleanup ---
    log_organizer "Cleaning up temporary download directory..."
    rm -rf "${DOWNLOAD_TMP_DIR}"
    log_organizer "✅ Organization complete."
}

# Execute the main function.
organize_files
