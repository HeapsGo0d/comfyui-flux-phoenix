#!/bin/bash
# ==================================================================================
# PHOENIX: FIXED FILE ORGANIZER SCRIPT
# ==================================================================================
# This script fixes the critical issues causing file organization failures

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

# --- Create Model Directory Structure (ENHANCED) ---
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
        debug_log "Creating directory: $dir"
        if mkdir -p "$dir" 2>/dev/null; then
            # Set appropriate permissions for ComfyUI access
            chmod 755 "$dir" 2>/dev/null || true
            debug_log "✅ Created/verified: $dir"
        else
            log_organizer "❌ CRITICAL: Failed to create directory: $dir"
            return 1
        fi
    done
    
    # Verify the parent models directory is accessible
    if [ ! -w "${MODELS_DIR}" ]; then
        log_organizer "❌ CRITICAL: Cannot write to models directory: ${MODELS_DIR}"
        ls -la "$(dirname "${MODELS_DIR}")" 2>/dev/null || true
        return 1
    fi
    
    debug_log "✅ All model directories created successfully"
    return 0
}

# --- Enhanced File Category Detection ---
determine_category() {
    local filename="$1"
    local filepath="$2"
    local filename_lower="${filename,,}"
    local filepath_lower="${filepath,,}"
    
    debug_log "Categorizing: $filename"
    
    # More specific pattern matching with priority order
    
    # VAE detection (highest priority for VAE files)
    if [[ "$filename_lower" =~ \.vae\. ]] || [[ "$filename_lower" =~ ^.*vae.*\.(safetensors|ckpt|pt|pth)$ ]] || [[ "$filepath_lower" =~ /vae/ ]]; then
        debug_log "Categorized as VAE: $filename"
        echo "vae"
        return
    fi
    
    # LoRA detection (high priority)
    if [[ "$filename_lower" =~ \.(lora|loha|locon|lycoris)\. ]] || [[ "$filepath_lower" =~ /lora/ ]]; then
        debug_log "Categorized as LoRA: $filename"
        echo "loras"
        return
    fi
    
    # ControlNet detection
    if [[ "$filename_lower" =~ (controlnet|t2i.adapter|t2iadapter) ]] || [[ "$filepath_lower" =~ controlnet ]]; then
        debug_log "Categorized as ControlNet: $filename"
        echo "controlnet"
        return
    fi
    
    # Upscaler detection
    if [[ "$filename_lower" =~ (upscale|esrgan|swinir|gfpgan|realesrgan|waifu2x) ]]; then
        debug_log "Categorized as Upscaler: $filename"
        echo "upscale_models"
        return
    fi
    
    # CLIP detection
    if [[ "$filename_lower" =~ clip ]] && [[ ! "$filename_lower" =~ (flux|unet) ]]; then
        debug_log "Categorized as CLIP: $filename"
        echo "clip"
        return
    fi
    
    # UNET detection (for FLUX models)
    if [[ "$filename_lower" =~ unet ]] || [[ "$filepath_lower" =~ unet ]]; then
        debug_log "Categorized as UNET: $filename"
        echo "unet"
        return
    fi
    
    # Embedding detection
    if [[ "$filename_lower" =~ (embedding|textual.inversion|\.ti\.) ]]; then
        debug_log "Categorized as Embedding: $filename"
        echo "embeddings"
        return
    fi
    
    # FLUX models go to diffusion_models
    if [[ "$filename_lower" =~ flux ]]; then
        debug_log "Categorized as FLUX (diffusion): $filename"
        echo "diffusion_models"
        return
    fi
    
    # Default to checkpoints for standard model files
    debug_log "Categorized as Checkpoint (default): $filename"
    echo "checkpoints"
}

# --- ENHANCED Move Function with Atomic Operations ---
move_file_to_destination() {
    local source_file="$1"
    local filename="$2"
    local category="$3"
    
    local destination_dir="${MODELS_DIR}/${category}"
    local destination_file="${destination_dir}/${filename}"
    local temp_destination="${destination_file}.tmp"
    
    debug_log "=== MOVE OPERATION START ==="
    debug_log "Source: $source_file"
    debug_log "Destination: $destination_file"
    
    # Pre-flight checks
    if [ ! -f "$source_file" ]; then
        log_organizer "❌ ERROR: Source file does not exist: $source_file"
        return 1
    fi
    
    if [ ! -r "$source_file" ]; then
        log_organizer "❌ ERROR: Source file is not readable: $source_file"
        ls -la "$source_file" 2>/dev/null || true
        return 1
    fi
    
    # Ensure destination directory exists with proper permissions
    if ! mkdir -p "$destination_dir" 2>/dev/null; then
        log_organizer "❌ ERROR: Cannot create destination directory: $destination_dir"
        return 1
    fi
    
    if [ ! -w "$destination_dir" ]; then
        log_organizer "❌ ERROR: Destination directory is not writable: $destination_dir"
        ls -la "$destination_dir" 2>/dev/null || true
        return 1
    fi
    
    # Check if file already exists
    if [ -f "$destination_file" ]; then
        local existing_size=$(stat -c%s "$destination_file" 2>/dev/null || echo "0")
        local source_size=$(stat -c%s "$source_file" 2>/dev/null || echo "0")
        
        if [ "$existing_size" -eq "$source_size" ] && [ "$existing_size" -gt 0 ]; then
            log_organizer "ℹ️ Skipping '${filename}' - identical file exists in ${category}/"
            rm -f "$source_file" 2>/dev/null || true  # Clean up source
            return 0
        else
            log_organizer "⚠️ File exists but different size - replacing: ${filename}"
        fi
    fi
    
    # ATOMIC MOVE: First move to temp name, then rename
    debug_log "Performing atomic move via temporary file..."
    
    if mv "$source_file" "$temp_destination" 2>/dev/null; then
        # Successfully moved to temp location, now rename to final
        if mv "$temp_destination" "$destination_file" 2>/dev/null; then
            # Verify the final file exists and is readable
            if [ -f "$destination_file" ] && [ -r "$destination_file" ]; then
                local final_size=$(stat -c%s "$destination_file" 2>/dev/null || echo "0")
                log_organizer "✅ Successfully moved '${filename}' to ${category}/ ($(numfmt --to=iec $final_size))"
                debug_log "Final file verified: readable and $(numfmt --to=iec $final_size)"
                return 0
            else
                log_organizer "❌ ERROR: Final file verification failed: $destination_file"
                return 1
            fi
        else
            log_organizer "❌ ERROR: Failed to rename temp file: $temp_destination"
            # Clean up temp file
            rm -f "$temp_destination" 2>/dev/null || true
            return 1
        fi
    else
        log_organizer "❌ ERROR: Failed initial move to temp location: $temp_destination"
        # Check if it's a cross-device issue
        if [ -f "$source_file" ]; then
            debug_log "Attempting copy+delete fallback..."
            if cp "$source_file" "$temp_destination" 2>/dev/null; then
                if mv "$temp_destination" "$destination_file" 2>/dev/null; then
                    rm -f "$source_file" 2>/dev/null || true
                    log_organizer "✅ Successfully copied '${filename}' to ${category}/ (fallback method)"
                    return 0
                else
                    rm -f "$temp_destination" 2>/dev/null || true
                fi
            fi
        fi
        return 1
    fi
}

# --- Pre-Organization Validation ---
validate_organization_readiness() {
    log_organizer "Validating organization readiness..."
    
    # Check if download directory exists and has content
    if [ ! -d "${DOWNLOAD_TMP_DIR}" ]; then
        log_organizer "No download directory found at: ${DOWNLOAD_TMP_DIR}"
        return 1
    fi
    
    # Count files to organize
    local file_count
    file_count=$(find "${DOWNLOAD_TMP_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) 2>/dev/null | wc -l)
    
    if [ "$file_count" -eq 0 ]; then
        log_organizer "No model files found to organize"
        return 1
    fi
    
    log_organizer "Found ${file_count} model files ready for organization"
    
    # Verify we can create model directories
    if ! create_model_directories; then
        log_organizer "❌ CRITICAL: Cannot create model directory structure"
        return 1
    fi
    
    debug_log "Organization readiness check passed"
    return 0
}

# --- ENHANCED Main Organizing Logic ---
organize_files() {
    log_organizer "Starting enhanced file organization process..."
    
    # Validate readiness first
    if ! validate_organization_readiness; then
        log_organizer "Organization readiness check failed - skipping"
        return 0
    fi
    
    # Initialize counters
    local total_files=0
    local successful_moves=0
    local failed_moves=0
    local skipped_files=0
    
    # Create a list of files to process (avoids issues with changing directory during processing)
    local temp_file_list="/tmp/files_to_organize.txt"
    find "${DOWNLOAD_TMP_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) > "$temp_file_list" 2>/dev/null
    
    total_files=$(wc -l < "$temp_file_list")
    log_organizer "Processing ${total_files} files..."
    
    local processed=0
    while IFS= read -r file; do
        [ -z "$file" ] && continue  # Skip empty lines
        
        ((processed++))
        local filename=$(basename "$file")
        local category
        category=$(determine_category "$filename" "$file")
        
        debug_log "Processing $processed/$total_files: $filename → $category"
        
        if move_file_to_destination "$file" "$filename" "$category"; then
            ((successful_moves++))
        else
            ((failed_moves++))
            log_organizer "⚠️ Failed to move: $filename"
        fi
        
        # Progress updates
        if [ $((processed % 5)) -eq 0 ] || [ "$processed" -eq "$total_files" ]; then
            log_organizer "Progress: $processed/$total_files processed ($successful_moves successful, $failed_moves failed)"
        fi
        
    done < "$temp_file_list"
    
    # Clean up temp file
    rm -f "$temp_file_list" 2>/dev/null || true
    
    # Final summary
    log_organizer "Organization complete: $successful_moves successful, $failed_moves failed"
    
    if [ "$failed_moves" -gt 0 ]; then
        log_organizer "❌ WARNING: $failed_moves files could not be moved!"
        log_organizer "Files remaining in download directory will be preserved"
        return 1
    fi
    
    return 0
}

# --- SAFE Cleanup Function (Only on Success) ---
cleanup_download_directory() {
    # Only clean up if organization was successful
    local remaining_model_files
    remaining_model_files=$(find "${DOWNLOAD_TMP_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) 2>/dev/null | wc -l)
    
    if [ "$remaining_model_files" -gt 0 ]; then
        log_organizer "⚠️ PRESERVATION: ${remaining_model_files} model files remain - NOT deleting download directory"
        log_organizer "Files preserved at: ${DOWNLOAD_TMP_DIR}"
        
        # List the files that couldn't be moved
        if [ "${DEBUG_MODE:-false}" = "true" ]; then
            debug_log "Preserved files:"
            find "${DOWNLOAD_TMP_DIR}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) | while read -r file; do
                debug_log "  $(basename "$file") ($(stat -c%s "$file" 2>/dev/null | numfmt --to=iec || echo "unknown size"))"
            done
        fi
        
        return 1
    else
        log_organizer "✅ All model files successfully organized - cleaning up download directory"
        rm -rf "${DOWNLOAD_TMP_DIR}" 2>/dev/null || true
        return 0
    fi
}

# --- Enhanced Success Verification ---
verify_organization_success() {
    log_organizer "Verifying organization results..."
    
    local total_organized=0
    local categories_with_files=()
    
    for category in checkpoints loras vae controlnet upscale_models embeddings clip unet diffusion_models; do
        local count=0
        if [ -d "${MODELS_DIR}/${category}" ]; then
            count=$(find "${MODELS_DIR}/${category}" -type f \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" \) 2>/dev/null | wc -l)
        fi
        
        if [ "$count" -gt 0 ]; then
            categories_with_files+=("$category: $count files")
            total_organized=$((total_organized + count))
        fi
    done
    
    if [ "$total_organized" -gt 0 ]; then
        log_organizer "✅ SUCCESS: ${total_organized} files successfully organized"
        for category_info in "${categories_with_files[@]}"; do
            log_organizer "  📁 ${category_info}"
        done
    else
        log_organizer "❌ FAILURE: No files found in final destinations"
        log_organizer "This indicates a critical organization failure"
        return 1
    fi
    
    return 0
}

# --- MAIN EXECUTION WITH ERROR HANDLING ---
main() {
    debug_log "Starting enhanced organizer with atomic operations..."
    
    # Step 1: Organize files
    local organization_success=true
    if ! organize_files; then
        organization_success=false
    fi
    
    # Step 2: Verify results
    if ! verify_organization_success; then
        organization_success=false
    fi
    
    # Step 3: Conditional cleanup
    if [ "$organization_success" = "true" ]; then
        cleanup_download_directory
        log_organizer "✅ File organization completed successfully"
    else
        log_organizer "⚠️ File organization completed with issues - download directory preserved"
        log_organizer "Manual intervention may be required"
    fi
    
    return 0
}

# Execute main function
main