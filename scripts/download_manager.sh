#!/bin/bash
# ==================================================================================
# PHOENIX: DOWNLOAD MANAGER SCRIPT
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

# --- Hugging Face Downloader ---
download_hf_repos() {
    # Check for Hugging Face token
    local token_arg=""
    if [ -n "${HUGGINGFACE_TOKEN:-}" ]; then
        token_arg="--token ${HUGGINGFACE_TOKEN}"
    fi

    # Read the comma-separated list of repos
    IFS=',' read -ra repos <<< "${HF_REPOS_TO_DOWNLOAD}"
    for repo_id in "${repos[@]}"; do
        # Trim whitespace
        repo_id=$(echo "${repo_id}" | xargs)
        if [ -z "$repo_id" ]; then continue; fi

        log_download "Starting HF download: ${repo_id}"
        # Download using huggingface-cli to a temp sub-directory
        huggingface-cli download \
            "${repo_id}" \
            --local-dir "${DOWNLOAD_TMP_DIR}/${repo_id}" \
            --local-dir-use-symlinks False \
            --resume-download \
            ${token_arg}
        log_download "✅ Completed HF download: ${repo_id}"
    done
}

# --- Civitai Downloader ---
# A robust function to download a single model from Civitai with checksum validation.
download_civitai_model() {
    local model_id=$1
    local model_type_for_log=$2

    # Fetch model metadata from Civitai API
    local api_url="https://civitai.com/api/v1/models/${model_id}"
    local model_data
    model_data=$(curl -s -H "Authorization: Bearer ${CIVITAI_TOKEN:-}" "${api_url}")

    # Use jq to parse the latest version's file info.
    # This assumes the first file of the latest version is the desired one.
    local file_info
    file_info=$(echo "${model_data}" | jq -r '.modelVersions[0].files[0] | {name, downloadUrl, "hash": .hashes.SHA256} | @json')

    if [ -z "$file_info" ] || [ "$file_info" == "null" ]; then
        log_download "❌ ERROR: Could not retrieve metadata for Civitai model ID ${model_id}. Skipping."
        return
    fi

    local filename download_url remote_hash
    filename=$(echo "$file_info" | jq -r '.name')
    download_url=$(echo "$file_info" | jq -r '.downloadUrl')
    remote_hash=$(echo "$file_info" | jq -r '.hash' | tr '[:upper:]' '[:lower:]')

    # --- Idempotency Check ---
    # Check if the file already exists in ANY of the potential final model directories.
    if find "${STORAGE_ROOT}/models/" -name "${filename}" -print -quit | grep -q .; then
        log_download "ℹ️ Skipping download for '${filename}', file already exists."
        return
    fi

    log_download "Starting Civitai download: ${filename} (${model_type_for_log})"

    # Download the file using aria2c for speed
    aria2c -x 16 -s 16 -k 1M --console-log-level=warn --summary-interval=0 \
        -d "${DOWNLOAD_TMP_DIR}" -o "${filename}" "${download_url}"

    # --- Checksum Validation ---
    log_download "Verifying checksum for ${filename}..."
    local local_hash
    local_hash=$(sha256sum "${DOWNLOAD_TMP_DIR}/${filename}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

    if [ "${local_hash}" == "${remote_hash}" ]; then
        log_download "✅ Checksum PASSED for ${filename}."
    else
        log_download "❌ ERROR: Checksum FAILED for ${filename}."
        log_download "   Expected: ${remote_hash}"
        log_download "   Got:      ${local_hash}"
        log_download "   Deleting corrupted file. Please try again."
        rm -f "${DOWNLOAD_TMP_DIR}/${filename}"
        exit 1 # Exit with error, as this is a critical failure.
    fi
}

# --- Main Orchestration Logic ---
log_download "Initializing download manager..."

# Process Hugging Face downloads
if [ -n "${HF_REPOS_TO_DOWNLOAD:-}" ]; then
    log_download "Found Hugging Face repos to download..."
    download_hf_repos
else
    log_download "No Hugging Face repos specified to download."
fi

# Process Civitai Checkpoint downloads
if [ -n "${CIVITAI_CHECKPOINTS_TO_DOWNLOAD:-}" ]; then
    log_download "Found Civitai Checkpoints to download..."
    IFS=',' read -ra ids <<< "${CIVITAI_CHECKPOINTS_TO_DOWNLOAD}"
    for id in "${ids[@]}"; do download_civitai_model "$(echo "$id" | xargs)" "Checkpoint"; done
else
    log_download "No Civitai Checkpoints specified to download."
fi

# Process Civitai LoRA downloads
if [ -n "${CIVITAI_LORAS_TO_DOWNLOAD:-}" ]; then
    log_download "Found Civitai LoRAs to download..."
    IFS=',' read -ra ids <<< "${CIVITAI_LORAS_TO_DOWNLOAD}"
    for id in "${ids[@]}"; do download_civitai_model "$(echo "$id" | xargs)" "LoRA"; done
else
    log_download "No Civitai LoRAs specified to download."
fi

# Process Civitai VAE downloads
if [ -n "${CIVITAI_VAES_TO_DOWNLOAD:-}" ]; then
    log_download "Found Civitai VAEs to download..."
    IFS=',' read -ra ids <<< "${CIVITAI_VAES_TO_DOWNLOAD}"
    for id in "${ids[@]}"; do download_civitai_model "$(echo "$id" | xargs)" "VAE"; done
else
    log_download "No Civitai VAEs specified to download."
fi


log_download "All downloads complete."
