#!/bin/bash
# ==================================================================================
# PHOENIX: FILE ORGANIZER SCRIPT (FIXED)
# ==================================================================================
# This script is sourced by entrypoint.sh. It intelligently moves files from the
# temporary download directory to their final destinations in the ComfyUI structure.

# --- Global Variables & Setup ---
readonly MODELS_DIR="${STORAGE_ROOT}/models"
readonly DOWNLOAD_TMP_DIR="/workspace/downloads_tmp"

# --- Logging Function ---
log_organizer() {
    echo "  [ORGANIZER] $1"
}

# --- Debug Logging Function ---
debug_log() {
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        echo "  [ORGANIZER-DEBUG] $1"
    fi
}

# --- Create Model Directory Structure ---
create_model_directories() {
    debug_log "Creating model directory structure..."
    
    local directories=(
        "${MODELS_DIR}/checkpoints"
        "${MODELS_DIR}/loras"
        "${MODELS_DIR}/vae"
        "${MODELS_DIR}/controlnet"
        "${MODELS_DIR}/upscale_models"
        "${MODELS_DIR}/embeddings"
        "${MODELS_DIR}/clip"
        "${MODELS_DIR}/unet"
        "${MODELS_DIR}/diffusion_models"
    )
    
    for dir in "${directories[@]}"; do
        if mkdir -p "$dir"; then
            debug_log "Created directory: $dir"
        else
            log_organizer "⚠️ Warning: Could not create directory: $dir"
        fi
    done
}

# --- Determine Model Category ---
determine_category() {
    local filename="$1"
    local filepath="$2"
    local filename_lower="${filename,,}"
    
    debug_log "Categorizing file: $filename"
    
    # Check file path for additional context
    local filepath_lower="${filepath,,}"
    
    # LoRA detection (most specific first)
    if [[ "$filename_lower" =~ (lora|loha|locon|lycoris) ]] || [[ "$filepath_lower" =~ lora ]]; then
        echo "loras"
        return
    fi
    
    # VAE detection
    if [[ "$filename_lower" =~ vae ]] || [[ "$filepath_lower" =~ vae ]]; then
        echo "vae"
        return
    fi
    
    # ControlNet detection
    if [[ "$filename_lower" =~ (controlnet|t2i.adapter|t2iadapter) ]] || [[ "$filepath_lower" =~ controlnet ]]; then
        echo "controlnet"
        return
    fi
    
    # Upscaler detection
    if [[ "$filename_lower" =~ (upscale|esrgan|swinir|gfpgan|realesrgan|waifu2x) ]] || [[ "$filepath_lower" =~ upscale ]]; then
        echo "upscale_models"
        return
    fi
    
    # Embedding detection
    if [[ "$filename_lower" =~ (embedding|textual.inversion|ti) ]] || [[ "$filepath_lower" =~ (embedding|textual) ]]; then
        echo "embeddings"
        return
    fi
    
    # CLIP detection
    if [[ "$filename_lower" =~ clip ]] || [[ "$filepath_lower" =~ clip ]]; then
        echo "clip"
        return
    fi
    
    # UNET detection (for FLUX and newer architectures)
    if [[ "$filename_lower" =~ unet ]] || [[ "$filepath_lower" =~ unet ]]; then
        echo "unet"
        return
    fi
    
    # Diffusion models (broader category)
    if [[ "$filename_lower" =~ (flux|sd3|sdxl|sd1\.5|sd2\.1|stable.diffusion) ]]; then
        echo "diffusion_models"
        return
    fi
    
    # Default to checkpoints for any unrecognized model files
    echo "checkpoints"
}

# --- Move File to Destination ---
move_file_to_destination() {
    local source_file="$1"
    local filename="$2"
    local category="$3"
    
    local destination_dir="${MODELS_DIR}/${category}"
    local destination_file="${destination_dir}/${filename}"
    
    # Check if file already exists at destination
    if [ -f "$destination_file" ]; then
        log_organizer "ℹ️ Skipping move for '${filename}', file already exists in ${category}/"
        debug_log "Existing file: $destination_file"
        return 0
    fi
    
    # Attempt to move the file
    debug_log "Moving '$filename' from downloads to ${category}/"
    if mv "$source_file" "$destination_file"; then
        log_organizer "✅ Moved '${filename}' to ${category}/"
        
        # Show file size in debug mode
        if [ "${DEBUG_MODE:-false}" = "true" ]; then
            local file_size=$(ls -lh "$destination_file" | awk '{print $5}')
            debug_log "File size: $file_size"
        fi
        return 0
    else
        log_organizer "❌ ERROR: Failed to move '${filename}' to ${category}/"
        return 1
    fi
}

# --- Main Organizing Logic ---
organize_files() {
    log_organizer "Starting file organization process..."
    
    # Create the directory structure first
    create_model_directories
    
    # Check if the temporary download directory exists
    if [ ! -d "${DOWNLOAD_TMP_DIR}" ]; then
        log_organizer "No download directory found. Nothing to organize."
        debug_log "Download directory does not exist: ${DOWNLOAD_TMP_DIR}"
        return 0
    fi
    
    # Check if directory is empty
    if [ -z "$(find "${DOWNLOAD_TMP_DIR}" -type f 2>/dev/null)" ]; then
        log_organizer "No files found in download directory. Nothing to organize."
        debug_log "Download directory is empty: ${DOWNLOAD_TMP_DIR}"
        return 0
    fi
    
    # Count total files for progress tracking
    local total_files
    total_files=$(find "${DOWNLOAD_TMP_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) | wc -l)
    
    if [ "$total_files" -eq 0 ]; then
        log_organizer "No model files found to organize."
        debug_log "No files with extensions: .safetensors, .ckpt, .pt, .pth, .bin"
        return 0
    fi
    
    log_organizer "Found ${total_files} model files to organize..."
    
    # Initialize counters
    local processed=0
    local successful=0
    local failed=0
    local skipped=0
    
    # Process all relevant model files
    find "${DOWNLOAD_TMP_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) -print0 | while IFS= read -r -d '' file; do
        ((processed++))
        
        local filename=$(basename "$file")
        local category
        category=$(determine_category "$filename" "$file")
        
        debug_log "Processing file $processed/$total_files: $filename -> $category"
        
        # Move the file
        if move_file_to_destination "$file" "$filename" "$category"; then
            ((successful++))
        else
            ((failed++))
        fi
        
        # Show progress in debug mode
        if [ "${DEBUG_MODE:-false}" = "true" ] && [ $((processed % 5)) -eq 0 ]; then
            debug_log "Progress: $processed/$total_files files processed"
        fi
    done
    
    # Get final counts (need to recount since we're in a subshell)
    local final_successful=0
    local final_failed=0
    
    # Count files that were successfully moved
    if [ -d "${MODELS_DIR}" ]; then
        final_successful=$(find "${MODELS_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) | wc -l)
    fi
    
    # Count files that remain in download directory
    if [ -d "${DOWNLOAD_TMP_DIR}" ]; then
        final_failed=$(find "${DOWNLOAD_TMP_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) | wc -l)
    fi
    
    log_organizer "Organization complete: ${final_successful} files organized"
    
    if [ "$final_failed" -gt 0 ]; then
        log_organizer "⚠️ Warning: ${final_failed} files could not be organized"
    fi
    
    # Show summary in debug mode
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        debug_log "=== ORGANIZATION SUMMARY ==="
        for category in checkpoints loras vae controlnet upscale_models embeddings clip unet diffusion_models; do
            local count=$(find "${MODELS_DIR}/${category}" -type f 2>/dev/null | wc -l)
            if [ "$count" -gt 0 ]; then
                debug_log "  ${category}/: ${count} files"
            fi
        done
        debug_log "=== END SUMMARY ==="
    fi
}

# --- Cleanup Function ---
cleanup_download_directory() {
    if [ -d "${DOWNLOAD_TMP_DIR}" ]; then
        # Check if there are any files left
        local remaining_files
        remaining_files=$(find "${DOWNLOAD_TMP_DIR}" -type f | wc -l)
        
        if [ "$remaining_files" -gt 0 ]; then
            log_organizer "⚠️ Warning: ${remaining_files} files remain in download directory"
            if [ "${DEBUG_MODE:-false}" = "true" ]; then
                debug_log "Remaining files:"
                find "${DOWNLOAD_TMP_DIR}" -type f | while read -r file; do
                    debug_log "  $(basename "$file")"
                done
            fi
        fi
        
        log_organizer "Cleaning up temporary download directory..."
        rm -rf "${DOWNLOAD_TMP_DIR}"
        debug_log "Download directory removed: ${DOWNLOAD_TMP_DIR}"
    fi
}

# --- Main Execution ---
organize_files
cleanup_download_directory
log_organizer "✅ File organization complete."

### DEBUG: debug_organizer.sh START
# Add these debug functions to organizer.sh

# --- Enhanced Debug Functions ---
debug_file_system() {
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        echo "  [ORGANIZER-DEBUG] === FILE SYSTEM STATE ==="
        echo "  [ORGANIZER-DEBUG] STORAGE_ROOT: ${STORAGE_ROOT}"
        echo "  [ORGANIZER-DEBUG] PWD: $(pwd)"
        echo "  [ORGANIZER-DEBUG] Downloads tmp exists: $([ -d "${DOWNLOAD_TMP_DIR}" ] && echo "YES" || echo "NO")"
        echo "  [ORGANIZER-DEBUG] Models dir exists: $([ -d "${MODELS_DIR}" ] && echo "YES" || echo "NO")"
        
        # Show all .safetensors files in the system
        echo "  [ORGANIZER-DEBUG] All .safetensors files in /workspace:"
        find /workspace -name "*.safetensors" -type f 2>/dev/null | while read -r file; do
            echo "  [ORGANIZER-DEBUG]   $(ls -la "$file" 2>/dev/null || echo "ERROR reading $file")"
        done
        
        # Show directory structure
        echo "  [ORGANIZER-DEBUG] /workspace structure:"
        ls -la /workspace/ 2>/dev/null | while read -r line; do
            echo "  [ORGANIZER-DEBUG]   $line"
        done
        
        if [ -d "${MODELS_DIR}" ]; then
            echo "  [ORGANIZER-DEBUG] Models directory structure:"
            find "${MODELS_DIR}" -type f 2>/dev/null | head -20 | while read -r file; do
                echo "  [ORGANIZER-DEBUG]   $(ls -la "$file")"
            done
        fi
        echo "  [ORGANIZER-DEBUG] === END FILE SYSTEM STATE ==="
    fi
}

# --- Enhanced Move Function with Tracing ---
move_file_to_destination() {
    local source_file="$1"
    local filename="$2"
    local category="$3"
    
    local destination_dir="${MODELS_DIR}/${category}"
    local destination_file="${destination_dir}/${filename}"
    
    debug_log "=== MOVE OPERATION START ==="
    debug_log "Source: $source_file"
    debug_log "Destination dir: $destination_dir"
    debug_log "Destination file: $destination_file"
    debug_log "Source exists: $([ -f "$source_file" ] && echo "YES" || echo "NO")"
    debug_log "Source size: $([ -f "$source_file" ] && ls -lh "$source_file" | awk '{print $5}' || echo "N/A")"
    debug_log "Destination dir exists: $([ -d "$destination_dir" ] && echo "YES" || echo "NO")"
    
    # Create destination directory with verbose logging
    if ! mkdir -p "$destination_dir"; then
        log_organizer "❌ ERROR: Failed to create directory: $destination_dir"
        debug_log "mkdir failed for: $destination_dir"
        return 1
    fi
    debug_log "Directory created/verified: $destination_dir"
    
    # Check if file already exists at destination
    if [ -f "$destination_file" ]; then
        log_organizer "ℹ️ Skipping move for '${filename}', file already exists in ${category}/"
        debug_log "File already exists: $destination_file"
        debug_log "Existing file size: $(ls -lh "$destination_file" | awk '{print $5}')"
        return 0
    fi
    
    # Attempt to move the file with detailed logging
    debug_log "Attempting move operation..."
    
    # Use set -x for this specific operation in debug mode
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        set -x
    fi
    
    if mv "$source_file" "$destination_file"; then
        if [ "${DEBUG_MODE:-false}" = "true" ]; then
            set +x
        fi
        
        log_organizer "✅ Moved '${filename}' to ${category}/"
        debug_log "Move successful!"
        debug_log "Final file exists: $([ -f "$destination_file" ] && echo "YES" || echo "NO")"
        debug_log "Final file size: $([ -f "$destination_file" ] && ls -lh "$destination_file" | awk '{print $5}' || echo "N/A")"
        debug_log "Final file permissions: $([ -f "$destination_file" ] && ls -la "$destination_file" | awk '{print $1,$3,$4}' || echo "N/A")"
        
        # Verify file is actually readable
        if [ -f "$destination_file" ] && [ -r "$destination_file" ]; then
            debug_log "✅ File is readable after move"
        else
            debug_log "❌ File is NOT readable after move!"
        fi
        
        debug_log "=== MOVE OPERATION SUCCESS ==="
        return 0
    else
        if [ "${DEBUG_MODE:-false}" = "true" ]; then
            set +x
        fi
        
        log_organizer "❌ ERROR: Failed to move '${filename}' to ${category}/"
        debug_log "Move operation failed!"
        debug_log "Source still exists: $([ -f "$source_file" ] && echo "YES" || echo "NO")"
        debug_log "Destination exists: $([ -f "$destination_file" ] && echo "YES" || echo "NO")"
        debug_log "=== MOVE OPERATION FAILED ==="
        return 1
    fi
}

# Add this at the start of organize_files()
organize_files() {
    log_organizer "Starting file organization process..."
    
    # Debug file system state before starting
    debug_file_system
    
    # ... rest of your existing organize_files function
}
### DEBUG: debug_organizer.sh END