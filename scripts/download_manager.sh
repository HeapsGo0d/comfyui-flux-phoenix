#!/bin/bash
# ==================================================================================
# PHOENIX: DOWNLOAD MANAGER SCRIPT (FIXED)
# ==================================================================================
# This script is sourced by entrypoint.sh. It handles downloading all required
# models and files from Hugging Face and Civitai based on ENV VARS.

# --- Global Variables & Setup ---
readonly DOWNLOAD_TMP_DIR="/workspace/downloads_tmp"
mkdir -p "${DOWNLOAD_TMP_DIR}"

# --- Logging Function ---
log_download() {
    echo "  [DOWNLOAD] $1"
}

# --- Debug Logging Function ---
debug_log() {
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        echo "  [DOWNLOAD-DEBUG] $1"
    fi
}

# --- Hugging Face Downloader (IMPROVED with Better Error Handling) ---
download_hf_repos() {
    # Skip if no repos specified
    if [ -z "${HF_REPOS_TO_DOWNLOAD:-}" ]; then
        log_download "No Hugging Face repos specified to download."
        return 0
    fi

    # Check for Hugging Face token
    local token_arg=""
    if [ -n "${HUGGINGFACE_TOKEN:-}" ]; then
        token_arg="--token ${HUGGINGFACE_TOKEN}"
        debug_log "Using provided HuggingFace token"
    else
        debug_log "No HuggingFace token provided"
    fi

    log_download "Found Hugging Face repos to download..."
    
    # Read the comma-separated list of repos
    IFS=',' read -ra repos <<< "${HF_REPOS_TO_DOWNLOAD}"
    for repo_id in "${repos[@]}"; do
        # Trim whitespace
        repo_id=$(echo "${repo_id}" | xargs)
        if [ -z "$repo_id" ]; then continue; fi

        log_download "Starting HF download: ${repo_id}"
        debug_log "Download directory: ${DOWNLOAD_TMP_DIR}/${repo_id}"
        
        # --- Improved Error Handling ---
        # Create a more detailed download command with progress in debug mode
        local download_cmd="huggingface-cli download \"${repo_id}\" --local-dir \"${DOWNLOAD_TMP_DIR}/${repo_id}\" --local-dir-use-symlinks False --resume-download ${token_arg}"
        
        if [ "${DEBUG_MODE:-false}" = "true" ]; then
            debug_log "Running: $download_cmd"
            # Show progress in debug mode
            if ! eval "$download_cmd"; then
                log_download "❌ ERROR: Failed to download '${repo_id}'."
                log_download "   This could be due to:"
                log_download "   - Invalid or expired token"
                log_download "   - Repository is private/gated and token lacks access"
                log_download "   - Repository doesn't exist or was moved"
                log_download "   - Network connectivity issues"
                log_download "   ⏭️ Continuing with remaining downloads..."
                continue
            fi
        else
            # Silent mode with error capture
            if ! eval "$download_cmd" &> /dev/null; then
                log_download "❌ ERROR: Failed to download '${repo_id}'."
                if [ -z "${HUGGINGFACE_TOKEN:-}" ]; then
                    log_download "   HINT: This is likely a private/gated repository. Please provide a"
                    log_download "   HUGGINGFACE_TOKEN via RunPod Secrets ('huggingface.co')."
                else
                    log_download "   HINT: Please check if your token is valid and has access to this repository."
                fi
                log_download "   ⏭️ Continuing with remaining downloads..."
                continue
            fi
        fi
        
        log_download "✅ Completed HF download: ${repo_id}"
        
        # Show download size in debug mode
        if [ "${DEBUG_MODE:-false}" = "true" ]; then
            local download_size=$(du -sh "${DOWNLOAD_TMP_DIR}/${repo_id}" 2>/dev/null | cut -f1 || echo "unknown")
            debug_log "Downloaded size: ${download_size}"
        fi
    done
}

# --- Civitai Downloader (FIXED) ---
download_civitai_model() {
    local model_id=$1
    local model_type_for_log=$2

    # Skip if model_id is empty
    if [ -z "$model_id" ]; then
        debug_log "Skipping empty model ID"
        return 0
    fi

    debug_log "Processing Civitai model ID: ${model_id}"

    # Build API URL with token if available
    local api_url="https://civitai.com/api/v1/models/${model_id}"
    local curl_cmd="curl -s"
    if [ -n "${CIVITAI_TOKEN:-}" ]; then
        curl_cmd="curl -s -H \"Authorization: Bearer ${CIVITAI_TOKEN}\""
        debug_log "Using Civitai token for API request"
    fi

    # Fetch model metadata from Civitai API
    debug_log "Fetching metadata from: ${api_url}"
    local model_data
    model_data=$(eval "${curl_cmd} \"${api_url}\"")

    # Check if API call was successful
    if [ -z "$model_data" ] || [ "$model_data" = "null" ]; then
        log_download "❌ ERROR: Could not retrieve metadata for Civitai model ID ${model_id}. API returned empty response."
        return 1
    fi

    # Use jq to parse the latest version's file info with better error handling
    local file_info
    file_info=$(echo "${model_data}" | jq -r '.modelVersions[0].files[0] | select(. != null) | {name, downloadUrl, "hash": .hashes.SHA256} | @json' 2>/dev/null)

    if [ -z "$file_info" ] || [ "$file_info" == "null" ]; then
        log_download "❌ ERROR: Could not parse file information for Civitai model ID ${model_id}."
        debug_log "API Response preview: $(echo "$model_data" | head -c 200)..."
        return 1
    fi

    local filename download_url remote_hash
    filename=$(echo "$file_info" | jq -r '.name' 2>/dev/null)
    download_url=$(echo "$file_info" | jq -r '.downloadUrl' 2>/dev/null)
    remote_hash=$(echo "$file_info" | jq -r '.hash' 2>/dev/null | tr '[:upper:]' '[:lower:]')

    # Validate parsed data
    if [ -z "$filename" ] || [ "$filename" = "null" ] || [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        log_download "❌ ERROR: Invalid file data for Civitai model ID ${model_id}."
        debug_log "Filename: $filename, Download URL: $download_url"
        return 1
    fi

    debug_log "Filename: $filename"
    debug_log "Download URL: ${download_url:0:50}..."
    debug_log "Remote hash: $remote_hash"

    # --- Idempotency Check ---
    if find "${STORAGE_ROOT}/models/" -name "${filename}" -print -quit 2>/dev/null | grep -q .; then
        log_download "ℹ️ Skipping download for '${filename}', file already exists."
        return 0
    fi

    log_download "Starting Civitai download: ${filename} (${model_type_for_log})"

    # Download the file using aria2c with progress display in debug mode
    local aria2_cmd="aria2c -x 16 -s 16 -k 1M --console-log-level=warn --summary-interval=0 -d \"${DOWNLOAD_TMP_DIR}\" -o \"${filename}\" \"${download_url}\""
    
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        # Show progress in debug mode
        aria2_cmd="aria2c -x 16 -s 16 -k 1M --console-log-level=info --summary-interval=10 -d \"${DOWNLOAD_TMP_DIR}\" -o \"${filename}\" \"${download_url}\""
        debug_log "Starting download with progress..."
    fi

    if ! eval "$aria2_cmd"; then
        log_download "❌ ERROR: Failed to download ${filename} from Civitai."
        return 1
    fi

    # --- Checksum Validation (if hash available) ---
    if [ -n "$remote_hash" ] && [ "$remote_hash" != "null" ]; then
        log_download "Verifying checksum for ${filename}..."
        local local_hash
        local_hash=$(sha256sum "${DOWNLOAD_TMP_DIR}/${filename}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

        if [ "${local_hash}" == "${remote_hash}" ]; then
            log_download "✅ Checksum PASSED for ${filename}."
        else
            log_download "❌ ERROR: Checksum FAILED for ${filename}."
            log_download "   Expected: ${remote_hash}"
            log_download "   Got:      ${local_hash}"
            log_download "   Deleting corrupted file..."
            rm -f "${DOWNLOAD_TMP_DIR}/${filename}"
            return 1
        fi
    else
        debug_log "No checksum available for ${filename}, skipping validation"
    fi

    log_download "✅ Completed Civitai download: ${filename}"
    return 0
}

# --- Process Civitai Downloads ---
process_civitai_downloads() {
    local download_list=$1
    local model_type=$2

    if [ -z "$download_list" ]; then
        log_download "No Civitai ${model_type}s specified to download."
        return 0
    fi

    log_download "Found Civitai ${model_type}s to download..."
    debug_log "Processing list: $download_list"

    # Split by comma and process each ID
    IFS=',' read -ra ids <<< "$download_list"
    local successful=0
    local failed=0
    
    for id in "${ids[@]}"; do
        # Trim whitespace
        id=$(echo "$id" | xargs)
        if [ -n "$id" ]; then
            if download_civitai_model "$id" "$model_type"; then
                ((successful++))
            else
                ((failed++))
                log_download "⏭️ Continuing with remaining ${model_type}s..."
            fi
        fi
    done

    log_download "Civitai ${model_type}s complete: ${successful} successful, ${failed} failed"
}

# --- Main Orchestration Logic ---
log_download "Initializing download manager..."

if [ "${DEBUG_MODE:-false}" = "true" ]; then
    debug_log "Debug mode enabled - showing detailed progress"
    debug_log "HF_REPOS_TO_DOWNLOAD: ${HF_REPOS_TO_DOWNLOAD:-<empty>}"
    debug_log "CIVITAI_CHECKPOINTS_TO_DOWNLOAD: ${CIVITAI_CHECKPOINTS_TO_DOWNLOAD:-<empty>}"
    debug_log "CIVITAI_LORAS_TO_DOWNLOAD: ${CIVITAI_LORAS_TO_DOWNLOAD:-<empty>}"
    debug_log "CIVITAI_VAES_TO_DOWNLOAD: ${CIVITAI_VAES_TO_DOWNLOAD:-<empty>}"
fi

# Process Hugging Face downloads
download_hf_repos

# Process Civitai downloads
process_civitai_downloads "${CIVITAI_CHECKPOINTS_TO_DOWNLOAD:-}" "Checkpoint"
process_civitai_downloads "${CIVITAI_LORAS_TO_DOWNLOAD:-}" "LoRA"
process_civitai_downloads "${CIVITAI_VAES_TO_DOWNLOAD:-}" "VAE"

log_download "All downloads complete."

# Debug summary if enabled
if [ "${DEBUG_MODE:-false}" = "true" ]; then
    debug_log "=== DOWNLOAD SUMMARY ==="
    if [ -d "${DOWNLOAD_TMP_DIR}" ]; then
        debug_log "Downloaded files:"
        find "${DOWNLOAD_TMP_DIR}" -type f -exec ls -lh {} \; 2>/dev/null | while read -r line; do 
            debug_log "  $line"
        done
        debug_log "Total download size: $(du -sh "${DOWNLOAD_TMP_DIR}" 2>/dev/null | cut -f1 || echo "unknown")"
    else
        debug_log "No files downloaded"
    fi
    debug_log "=== END SUMMARY ==="
fi