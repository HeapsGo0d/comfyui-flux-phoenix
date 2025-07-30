#!/bin/bash
# ==================================================================================
# PHOENIX: DOWNLOAD MANAGER SCRIPT (ENHANCED)
# ==================================================================================
# This script is sourced by entrypoint.sh. It handles downloading all required
# models and files from Hugging Face and Civitai based on ENV VARS.

# --- Logging Function ---
log_download() {
    echo "  [DOWNLOAD] $1"
}

# --- Environment Validation ---
validate_environment() {
    if [ -z "${DOWNLOAD_TMP_DIR:-}" ]; then
        log_download "❌ ERROR: DOWNLOAD_TMP_DIR not set. System setup may have failed."
        exit 1
    fi
    
    # Create download directory
    mkdir -p "${DOWNLOAD_TMP_DIR}"
    
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        log_download "DEBUG: Using download directory: ${DOWNLOAD_TMP_DIR}"
        log_download "DEBUG: Available disk space:"
        df -h "${DOWNLOAD_TMP_DIR}" | tail -1 | awk '{print "  Free: " $4 " / Total: " $2}'
    fi
}

# --- Hugging Face Downloader (IMPROVED with Better Error Handling) ---
download_hf_repos() {
    local token_arg=""
    if [ -n "${HUGGINGFACE_TOKEN:-}" ]; then
        token_arg="--token ${HUGGINGFACE_TOKEN}"
        if [ "${DEBUG_MODE:-false}" = "true" ]; then
            log_download "DEBUG: Using provided Hugging Face token"
        fi
    else
        log_download "INFO: No Hugging Face token provided. Only public repositories will be accessible."
    fi

    # Parse repos, handling both comma and space separation
    local repos_raw="${HF_REPOS_TO_DOWNLOAD}"
    repos_raw=$(echo "$repos_raw" | tr ',' ' ' | tr -s ' ')
    
    if [ -z "$repos_raw" ]; then
        log_download "No Hugging Face repositories specified"
        return
    fi
    
    # Convert to array
    local -a repos
    read -ra repos <<< "$repos_raw"
    
    log_download "Processing ${#repos[@]} Hugging Face repositories..."
    
    for repo_id in "${repos[@]}"; do
        # Trim whitespace
        repo_id=$(echo "${repo_id}" | xargs)
        if [ -z "$repo_id" ]; then continue; fi

        log_download "Starting HF download: ${repo_id}"
        
        local repo_dir="${DOWNLOAD_TMP_DIR}/hf_${repo_id//\//_}"
        
        # Check if already downloaded
        if [ -d "$repo_dir" ] && [ "$(ls -A "$repo_dir" 2>/dev/null)" ]; then
            log_download "ℹ️ Repository '${repo_id}' already exists. Skipping download."
            continue
        fi
        
        # Attempt download with better error handling
        local download_success=false
        local max_retries=3
        local retry_count=0
        
        while [ $retry_count -lt $max_retries ] && [ "$download_success" = false ]; do
            if [ $retry_count -gt 0 ]; then
                log_download "Retry attempt ${retry_count}/${max_retries} for ${repo_id}"
                sleep $((retry_count * 5))  # Exponential backoff: 5s, 10s, 15s
            fi
            
            if huggingface-cli download \
                "${repo_id}" \
                --local-dir "${repo_dir}" \
                --local-dir-use-symlinks False \
                --resume-download \
                ${token_arg} 2>/dev/null; then
                
                download_success=true
                log_download "✅ Completed HF download: ${repo_id}"
                
                # Debug: Show what was downloaded
                if [ "${DEBUG_MODE:-false}" = "true" ]; then
                    local file_count=$(find "$repo_dir" -type f | wc -l)
                    local total_size=$(du -sh "$repo_dir" 2>/dev/null | cut -f1 || echo "unknown")
                    log_download "DEBUG: Downloaded ${file_count} files, total size: ${total_size}"
                fi
                
            else
                retry_count=$((retry_count + 1))
                if [ $retry_count -ge $max_retries ]; then
                    log_download "❌ ERROR: Failed to download '${repo_id}' after ${max_retries} attempts."
                    if [ -z "${HUGGINGFACE_TOKEN:-}" ]; then
                        log_download "   HINT: This might be a private/gated repository. Try providing HUGGINGFACE_TOKEN."
                    else
                        log_download "   HINT: Check if your token has access to this repository or if there are network issues."
                    fi
                    # Clean up partial download
                    rm -rf "$repo_dir"
                fi
            fi
        done
    done
}

# --- Civitai Downloader (Enhanced with Better Error Handling) ---
download_civitai_model() {
    local model_id="$1"
    local model_type_for_log="$2"
    
    if [ -z "$model_id" ]; then
        log_download "❌ ERROR: Empty model ID provided to Civitai downloader"
        return 1
    fi

    log_download "Processing Civitai ${model_type_for_log} ID: ${model_id}"

    # Fetch model metadata from Civitai API with timeout and retries
    local api_url="https://civitai.com/api/v1/models/${model_id}"
    local model_data
    local auth_header=""
    
    if [ -n "${CIVITAI_TOKEN:-}" ]; then
        auth_header="Authorization: Bearer ${CIVITAI_TOKEN}"
    fi
    
    # Try to fetch metadata with retries
    local fetch_success=false
    local max_retries=3
    
    for attempt in $(seq 1 $max_retries); do
        if [ -n "$auth_header" ]; then
            model_data=$(curl -s --max-time 30 -H "$auth_header" "$api_url" 2>/dev/null)
        else
            model_data=$(curl -s --max-time 30 "$api_url" 2>/dev/null)
        fi
        
        if [ -n "$model_data" ] && echo "$model_data" | jq -e '.modelVersions[0]' >/dev/null 2>&1; then
            fetch_success=true
            break
        fi
        
        if [ $attempt -lt $max_retries ]; then
            log_download "API request failed, retrying in $((attempt * 2)) seconds..."
            sleep $((attempt * 2))
        fi
    done
    
    if [ "$fetch_success" = false ]; then
        log_download "❌ ERROR: Could not retrieve metadata for Civitai model ID ${model_id} after ${max_retries} attempts."
        return 1
    fi

    # Parse file information
    local file_info
    file_info=$(echo "$model_data" | jq -r '.modelVersions[0].files[0] | {name, downloadUrl, "hash": .hashes.SHA256} | @json' 2>/dev/null)

    if [ -z "$file_info" ] || [ "$file_info" == "null" ]; then
        log_download "❌ ERROR: Could not parse file information for model ID ${model_id}"
        return 1
    fi

    local filename download_url remote_hash
    filename=$(echo "$file_info" | jq -r '.name' 2>/dev/null)
    download_url=$(echo "$file_info" | jq -r '.downloadUrl' 2>/dev/null)
    remote_hash=$(echo "$file_info" | jq -r '.hash' 2>/dev/null | tr '[:upper:]' '[:lower:]')

    if [ -z "$filename" ] || [ "$filename" == "null" ]; then
        log_download "❌ ERROR: Could not extract filename for model ID ${model_id}"
        return 1
    fi

    # Check if file already exists anywhere in models directory
    if [ -n "${STORAGE_ROOT:-}" ] && find "${STORAGE_ROOT}/models/" -name "${filename}" -print -quit 2>/dev/null | grep -q .; then
        log_download "ℹ️ File '${filename}' already exists in models directory. Skipping download."
        return 0
    fi

    log_download "Downloading: ${filename} (${model_type_for_log})"

    # Download with aria2c and enhanced error handling
    local download_success=false
    local download_attempts=0
    local max_download_attempts=3
    
    while [ $download_attempts -lt $max_download_attempts ] && [ "$download_success" = false ]; do
        download_attempts=$((download_attempts + 1))
        
        if [ $download_attempts -gt 1 ]; then
            log_download "Download attempt ${download_attempts}/${max_download_attempts} for ${filename}"
        fi
        
        # Check available disk space before download
        local available_space=$(df "${DOWNLOAD_TMP_DIR}" | tail -1 | awk '{print $4}')
        if [ "$available_space" -lt 1000000 ]; then  # Less than ~1GB
            log_download "❌ ERROR: Insufficient disk space for download. Available: ${available_space}KB"
            return 1
        fi
        
        if aria2c -x 16 -s 16 -k 1M \
            --console-log-level=warn \
            --summary-interval=0 \
            --max-tries=3 \
            --retry-wait=10 \
            --timeout=300 \
            --max-file-not-found=3 \
            -d "${DOWNLOAD_TMP_DIR}" \
            -o "${filename}" \
            "${download_url}" 2>/dev/null; then
            
            download_success=true
        else
            log_download "Download attempt ${download_attempts} failed for ${filename}"
            # Clean up partial download
            rm -f "${DOWNLOAD_TMP_DIR}/${filename}"*
            
            if [ $download_attempts -lt $max_download_attempts ]; then
                sleep $((download_attempts * 5))
            fi
        fi
    done
    
    if [ "$download_success" = false ]; then
        log_download "❌ ERROR: Failed to download ${filename} after ${max_download_attempts} attempts"
        return 1
    fi

    # Checksum validation (if hash is available)
    if [ -n "$remote_hash" ] && [ "$remote_hash" != "null" ] && [ ${#remote_hash} -eq 64 ]; then
        log_download "Verifying checksum for ${filename}..."
        local local_hash
        local_hash=$(sha256sum "${DOWNLOAD_TMP_DIR}/${filename}" 2>/dev/null | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

        if [ "${local_hash}" = "${remote_hash}" ]; then
            log_download "✅ Checksum verification PASSED for ${filename}"
        else
            log_download "❌ ERROR: Checksum verification FAILED for ${filename}"
            log_download "   Expected: ${remote_hash}"
            log_download "   Got:      ${local_hash}"
            log_download "   Removing corrupted file."
            rm -f "${DOWNLOAD_TMP_DIR}/${filename}"
            return 1
        fi
    else
        log_download "⚠️ No valid checksum available for ${filename}, skipping verification"
    fi
    
    log_download "✅ Successfully downloaded: ${filename}"
    return 0
}

# --- Process Civitai Downloads ---
process_civitai_downloads() {
    local download_type="$1"
    local ids_var="$2"
    local display_name="$3"
    
    local ids_string="${!ids_var:-}"
    
    if [ -z "$ids_string" ]; then
        log_download "No Civitai ${display_name} specified to download."
        return
    fi
    
    log_download "Found Civitai ${display_name} to download..."
    
    # Parse IDs, handling both comma and space separation
    ids_string=$(echo "$ids_string" | tr ',' ' ' | tr -s ' ')
    local -a ids
    read -ra ids <<< "$ids_string"
    
    log_download "Processing ${#ids[@]} ${display_name} IDs..."
    
    local success_count=0
    local total_count=${#ids[@]}
    
    for id in "${ids[@]}"; do
        id=$(echo "$id" | xargs)  # Trim whitespace
        if [ -z "$id" ]; then continue; fi
        
        if download_civitai_model "$id" "$display_name"; then
            success_count=$((success_count + 1))
        fi
    done
    
    log_download "Completed ${display_name} downloads: ${success_count}/${total_count} successful"
}

# --- Main Orchestration Logic ---
main() {
    log_download "Initializing download manager..."
    
    validate_environment
    
    # Process Hugging Face downloads
    if [ -n "${HF_REPOS_TO_DOWNLOAD:-}" ]; then
        download_hf_repos
    fi
    
    # Process Civitai downloads
    process_civitai_downloads "checkpoint" "CIVITAI_CHECKPOINTS_TO_DOWNLOAD" "Checkpoints"
    process_civitai_downloads "lora" "CIVITAI_LORAS_TO_DOWNLOAD" "LoRAs"
    process_civitai_downloads "vae" "CIVITAI_VAES_TO_DOWNLOAD" "VAEs"
    
    log_download "All downloads complete."
    
    # Show summary in debug mode
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        log_download "DEBUG: Download summary:"
        if [ -d "${DOWNLOAD_TMP_DIR}" ]; then
            local total_files=$(find "${DOWNLOAD_TMP_DIR}" -type f | wc -l)
            local total_size=$(du -sh "${DOWNLOAD_TMP_DIR}" 2>/dev/null | cut -f1 || echo "unknown")
            log_download "  Total files: ${total_files}"
            log_download "  Total size: ${total_size}"
        fi
    fi
}

# Execute main function
main