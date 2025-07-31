#!/bin/bash
# ==================================================================================
# PHOENIX: GRACEFUL DOWNLOAD MANAGER (NO-FAIL MODE)
# ==================================================================================
# This script handles downloads gracefully - failures don't crash the container

# --- Safety Setup ---
set -euo pipefail
umask 077

# --- Logging Function ---
log_download() {
    echo "  [DOWNLOAD] $1"
}

# --- Configuration Validation ---
validate_configuration() {
    log_download "Validating download configuration..."
    
    # Check essential environment
    if [ -z "${DOWNLOAD_TMP_DIR:-}" ]; then
        log_download "❌ ERROR: DOWNLOAD_TMP_DIR not set"
        return 1
    fi
    
    if [ -z "${STORAGE_ROOT:-}" ]; then
        log_download "❌ ERROR: STORAGE_ROOT not set"
        return 1
    fi
    
    # Create/verify download directory
    mkdir -p "${DOWNLOAD_TMP_DIR}"
    chmod 700 "${DOWNLOAD_TMP_DIR}"
    
    # Check available space
    local available_gb=$(df -BG "${DOWNLOAD_TMP_DIR}" | awk 'NR==2 {print $4}' | sed 's/G//')
    log_download "Available storage: ${available_gb}GB"
    
    if [ "$available_gb" -lt 10 ]; then
        log_download "⚠️ WARNING: Low storage space (${available_gb}GB)"
        log_download "   Large model downloads may fail"
    fi
    
    return 0
}

# --- Token Status Check ---
check_token_status() {
    local service="$1"
    local token_var="$2"
    local token_value="${!token_var:-}"
    
    if [ -n "$token_value" ]; then
        if [ ${#token_value} -gt 10 ]; then
            log_download "✅ ${service} token: Available (${#token_value} chars)"
            return 0
        else
            log_download "⚠️ ${service} token: Too short (${#token_value} chars) - likely invalid"
            return 1
        fi
    else
        log_download "ℹ️ ${service} token: Not provided - only public content accessible"
        return 1
    fi
}

# --- Robust HuggingFace Downloader ---
download_hf_repos() {
    log_download "=== HUGGINGFACE DOWNLOAD PHASE ==="
    
    # Check for repos to download
    local repos_raw="${HF_REPOS_TO_DOWNLOAD:-}"
    if [ -z "$repos_raw" ]; then
        log_download "No HuggingFace repositories specified. Skipping."
        return 0
    fi
    
    # Check token status
    local has_token=false
    if check_token_status "HuggingFace" "HUGGINGFACE_TOKEN"; then
        has_token=true
        export HUGGING_FACE_HUB_TOKEN="${HUGGINGFACE_TOKEN}"
    fi
    
    # Parse repository list
    repos_raw=$(echo "$repos_raw" | tr ',' ' ' | tr -s ' ')
    local -a repos
    read -ra repos <<< "$repos_raw"
    
    log_download "Processing ${#repos[@]} HuggingFace repositories..."
    
    local success_count=0
    local total_count=${#repos[@]}
    
    for repo_id in "${repos[@]}"; do
        repo_id=$(echo "${repo_id}" | xargs)
        if [ -z "$repo_id" ]; then continue; fi
        
        # Validate repo ID format
        if [[ ! "$repo_id" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
            log_download "⚠️ Invalid repository format: $repo_id (skipping)"
            continue
        fi
        
        log_download "Downloading: ${repo_id}"
        
        local repo_dir="${DOWNLOAD_TMP_DIR}/hf_${repo_id//\//_}"
        
        # Check if already exists
        if [ -d "$repo_dir" ] && [ "$(ls -A "$repo_dir" 2>/dev/null)" ]; then
            log_download "✅ Repository already exists: ${repo_id}"
            success_count=$((success_count + 1))
            continue
        fi
        
        # Create repo directory
        mkdir -p "$repo_dir"
        
        # Attempt download with retries
        local download_success=false
        local max_attempts=3
        
        for attempt in $(seq 1 $max_attempts); do
            if [ $attempt -gt 1 ]; then
                log_download "Retry ${attempt}/${max_attempts} for ${repo_id}"
                sleep $((attempt * 5))
            fi
            
            # Download with timeout and error handling
            local download_cmd="huggingface-cli download \"${repo_id}\" --local-dir \"${repo_dir}\" --local-dir-use-symlinks False --resume-download"
            
            if [ "$has_token" = true ]; then
                download_cmd="${download_cmd} --token \$HUGGING_FACE_HUB_TOKEN"
            fi
            
            if timeout 1800 bash -c "$download_cmd" >/dev/null 2>&1; then
                download_success=true
                break
            else
                log_download "Attempt ${attempt} failed for ${repo_id}"
                # Clean up partial download
                rm -rf "$repo_dir"
                mkdir -p "$repo_dir"
            fi
        done
        
        if [ "$download_success" = true ]; then
            log_download "✅ Successfully downloaded: ${repo_id}"
            success_count=$((success_count + 1))
            
            # Show download size in debug mode
            if [ "${DEBUG_MODE:-false}" = "true" ]; then
                local repo_size=$(du -sh "$repo_dir" 2>/dev/null | cut -f1 || echo "unknown")
                local file_count=$(find "$repo_dir" -type f | wc -l)
                log_download "  Size: ${repo_size}, Files: ${file_count}"
            fi
        else
            log_download "❌ Failed to download: ${repo_id}"
            if [ "$has_token" = false ]; then
                log_download "   HINT: This may be a private repository requiring authentication"
                log_download "   Consider providing HUGGINGFACE_TOKEN via RunPod secrets"
            fi
            rm -rf "$repo_dir"
        fi
    done
    
    log_download "HuggingFace downloads complete: ${success_count}/${total_count} successful"
    
    # Clear token from environment
    unset HUGGING_FACE_HUB_TOKEN 2>/dev/null || true
    
    return 0  # Always return success to prevent container exit
}

# --- Graceful Civitai Downloader ---
download_civitai_model() {
    local model_id="$1"
    local model_type="$2"
    local has_token="$3"
    
    # Validate model ID
    if [[ ! "$model_id" =~ ^[0-9]+$ ]]; then
        log_download "⚠️ Invalid Civitai model ID: $model_id (skipping)"
        return 1
    fi
    
    log_download "Processing Civitai ${model_type} ID: ${model_id}"
    
    # Fetch model metadata with graceful error handling
    local api_url="https://civitai.com/api/v1/models/${model_id}"
    local model_data=""
    local fetch_success=false
    
    for attempt in {1..3}; do
        if [ $attempt -gt 1 ]; then
            log_download "API retry ${attempt}/3 for model ${model_id}"
            sleep $((attempt * 2))
        fi
        
        if [ "$has_token" = true ]; then
            model_data=$(timeout 30 curl -s -H "Authorization: Bearer ${CIVITAI_TOKEN}" "$api_url" 2>/dev/null || echo "")
        else
            model_data=$(timeout 30 curl -s "$api_url" 2>/dev/null || echo "")
        fi
        
        # Validate JSON response
        if [ -n "$model_data" ] && echo "$model_data" | jq -e '.modelVersions[0]' >/dev/null 2>&1; then
            fetch_success=true
            break
        fi
    done
    
    if [ "$fetch_success" = false ]; then
        log_download "❌ Could not fetch metadata for model ${model_id}"
        if [ "$has_token" = false ]; then
            log_download "   HINT: This may be a private model requiring authentication"
        fi
        return 1
    fi
    
    # Parse file information safely
    local file_info filename download_url remote_hash
    
    if ! file_info=$(echo "$model_data" | jq -r '.modelVersions[0].files[0] | {name, downloadUrl, "hash": .hashes.SHA256} | @json' 2>/dev/null); then
        log_download "❌ Could not parse file data for model ${model_id}"
        return 1
    fi
    
    filename=$(echo "$file_info" | jq -r '.name' 2>/dev/null)
    download_url=$(echo "$file_info" | jq -r '.downloadUrl' 2>/dev/null)
    remote_hash=$(echo "$file_info" | jq -r '.hash' 2>/dev/null)
    
    if [ -z "$filename" ] || [ "$filename" = "null" ]; then
        log_download "❌ Invalid filename for model ${model_id}"
        return 1
    fi
    
    # Check if file already exists
    if [ -n "${STORAGE_ROOT:-}" ] && find "${STORAGE_ROOT}/models/" -name "$filename" -print -quit 2>/dev/null | grep -q .; then
        log_download "✅ File already exists: $filename"
        return 0
    fi
    
    log_download "Downloading: $filename"
    
    # Download with graceful error handling
    local download_success=false
    local max_attempts=3
    
    for attempt in $(seq 1 $max_attempts); do
        if [ $attempt -gt 1 ]; then
            log_download "Download retry ${attempt}/${max_attempts} for ${filename}"
            sleep $((attempt * 5))
        fi
        
        # Check available space before each attempt
        local available_kb=$(df "${DOWNLOAD_TMP_DIR}" | tail -1 | awk '{print $4}')
        if [ "$available_kb" -lt 2097152 ]; then  # Less than 2GB
            log_download "❌ Insufficient disk space for ${filename}"
            return 1
        fi
        
        # Download with aria2c
        if timeout 1800 aria2c \
            --max-concurrent-downloads=1 \
            --max-connection-per-server=8 \
            --split=8 \
            --min-split-size=1M \
            --console-log-level=error \
            --summary-interval=0 \
            --max-tries=2 \
            --retry-wait=10 \
            --timeout=300 \
            --dir="${DOWNLOAD_TMP_DIR}" \
            --out="${filename}" \
            "${download_url}" >/dev/null 2>&1; then
            
            download_success=true
            break
        else
            log_download "Download attempt ${attempt} failed for ${filename}"
            rm -f "${DOWNLOAD_TMP_DIR}/${filename}"*
        fi
    done
    
    if [ "$download_success" = true ]; then
        # Verify hash if available
        if [ -n "$remote_hash" ] && [ "$remote_hash" != "null" ] && [ ${#remote_hash} -eq 64 ]; then
            local local_hash=$(sha256sum "${DOWNLOAD_TMP_DIR}/${filename}" 2>/dev/null | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
            remote_hash=$(echo "$remote_hash" | tr '[:upper:]' '[:lower:]')
            
            if [ "$local_hash" = "$remote_hash" ]; then
                log_download "✅ Downloaded and verified: $filename"
            else
                log_download "⚠️ Checksum mismatch for $filename (keeping file anyway)"
            fi
        else
            log_download "✅ Downloaded: $filename (no checksum available)"
        fi
        return 0
    else
        log_download "❌ Failed to download: $filename"
        return 1
    fi
}

# --- Process Civitai Downloads ---
process_civitai_downloads() {
    local download_type="$1"
    local ids_var="$2"
    local display_name="$3"
    
    log_download "=== CIVITAI ${display_name^^} DOWNLOAD PHASE ==="
    
    local ids_string="${!ids_var:-}"
    if [ -z "$ids_string" ]; then
        log_download "No Civitai ${display_name} specified. Skipping."
        return 0
    fi
    
    # Check token status
    local has_token=false
    if check_token_status "Civitai" "CIVITAI_TOKEN"; then
        has_token=true
    fi
    
    # Parse and validate IDs
    ids_string=$(echo "$ids_string" | tr ',' ' ' | tr -s ' ')
    local -a ids valid_ids
    read -ra ids <<< "$ids_string"
    
    for id in "${ids[@]}"; do
        id=$(echo "$id" | xargs)
        if [[ "$id" =~ ^[0-9]+$ ]] && [ ${#id} -le 10 ]; then
            valid_ids+=("$id")
        else
            log_download "⚠️ Invalid ${display_name} ID: $id (skipping)"
        fi
    done
    
    if [ ${#valid_ids[@]} -eq 0 ]; then
        log_download "No valid ${display_name} IDs found"
        return 0
    fi
    
    log_download "Processing ${#valid_ids[@]} ${display_name} IDs..."
    
    local success_count=0
    for id in "${valid_ids[@]}"; do
        if download_civitai_model "$id" "$display_name" "$has_token"; then
            success_count=$((success_count + 1))
        fi
        
        # Be respectful to the API
        sleep 2
    done
    
    log_download "Civitai ${display_name} downloads: ${success_count}/${#valid_ids[@]} successful"
    return 0
}

# --- Main Download Orchestration ---
main() {
    log_download "Initializing graceful download manager..."
    
    # Validate configuration (critical - must succeed)
    if ! validate_configuration; then
        log_download "❌ FATAL: Configuration validation failed"
        exit 1
    fi
    
    local total_errors=0
    
    # HuggingFace downloads (non-fatal)
    if [ -n "${HF_REPOS_TO_DOWNLOAD:-}" ]; then
        if ! download_hf_repos; then
            log_download "⚠️ HuggingFace download phase had issues"
            total_errors=$((total_errors + 1))
        fi
    else
        log_download "No HuggingFace repositories configured"
    fi
    
    # Civitai downloads (non-fatal)
    if ! process_civitai_downloads "checkpoint" "CIVITAI_CHECKPOINTS_TO_DOWNLOAD" "Checkpoints"; then
        total_errors=$((total_errors + 1))
    fi
    
    if ! process_civitai_downloads "lora" "CIVITAI_LORAS_TO_DOWNLOAD" "LoRAs"; then
        total_errors=$((total_errors + 1))
    fi
    
    if ! process_civitai_downloads "vae" "CIVITAI_VAES_TO_DOWNLOAD" "VAEs"; then
        total_errors=$((total_errors + 1))
    fi
    
    # Summary
    if [ $total_errors -eq 0 ]; then
        log_download "✅ All download phases completed successfully"
    else
        log_download "⚠️ Download completed with ${total_errors} phase(s) having issues"
        log_download "   Container will continue - partial downloads are acceptable"
    fi
    
    # Show final status
    if [ -d "${DOWNLOAD_TMP_DIR}" ]; then
        local total_files=$(find "${DOWNLOAD_TMP_DIR}" -type f | wc -l)
        if [ $total_files -gt 0 ]; then
            local total_size=$(du -sh "${DOWNLOAD_TMP_DIR}" 2>/dev/null | cut -f1 || echo "unknown")
            log_download "Downloaded: ${total_files} files, ${total_size} total"
        else
            log_download "No files were downloaded (this may be normal)"
        fi
    fi
    
    log_download "Download manager completed gracefully"
    return 0  # Always return success
}

# Execute main function
main