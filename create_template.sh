#!/usr/bin/env bash
set -euo pipefail

# ==================================================================================
# PHOENIX: RUNPOD TEMPLATE DEPLOYMENT SCRIPT
# ==================================================================================
# This script creates or updates the RunPod template for Project Phoenix.

# ─── Configuration ──────────────────────────────────────────────────────────
# ⚠️ IMPORTANT: Update this to your Docker Hub username and image name.
readonly IMAGE_NAME="joyc0025/comfyui-flux-phoenix:v1.2-test3"
readonly TEMPLATE_NAME="ComfyUI FLUX - Project Phoenix"

# ─── Pre-flight Checks ──────────────────────────────────────────────────────
if [[ -z "${RUNPOD_API_KEY:-}" ]]; then
  echo "❌ Error: RUNPOD_API_KEY environment variable is not set." >&2
  echo "   Please set it with: export RUNPOD_API_KEY='your_api_key'" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo "❌ Error: This script requires 'jq' and 'curl'. Please install them." >&2
  exit 1
fi
echo "✅ Pre-flight checks passed."

# ─── README Content Definition ──────────────────────────────────────────────
# This README is generated from our project's v1.1 requirements.
README_CONTENT=$(cat <<'EOF'
# ComfyUI FLUX - Project Phoenix

This template provides a production-ready, secure, and high-performance environment for ComfyUI with FLUX models, specifically optimized for the latest NVIDIA GPUs (RTX 40/50 series).

### 🌟 Key Features:
- **Optimized for Modern GPUs**: Built on the official NVIDIA PyTorch container for maximum performance and compatibility.
- **Version Pinned Stability**: Key components like ComfyUI are version-pinned for reliable, repeatable deployments.
- **Advanced Security**: Runs as a non-root user, uses secure default permissions (`umask 077`), and performs a "leave-no-trace" forensic cleanup of all logs, caches, and temporary files on exit.
- **Flexible Storage**: Seamlessly supports both ephemeral sessions and persistent volumes (`/runpod-volume`).
- **Automated Downloads & Organization**: Intelligently downloads from Hugging Face & Civitai (with checksum validation) and automatically organizes files into the correct ComfyUI directories.

### 🖥️ Services & Ports:
- **ComfyUI**: Port `8188`
- **FileBrowser**: Port `8080` (serves the entire `/workspace`)

### ⚙️ Environment Variables (See Template Options):
- **Basic**: `HF_REPOS_TO_DOWNLOAD`, `CIVITAI_CHECKPOINTS_TO_DOWNLOAD`, `FB_PASSWORD`, etc.
- **Advanced**: `DEBUG_MODE`, `PARANOID_MODE` (for enhanced cleanup), `USE_VOLUME`.
- All tokens (`HUGGINGFACE_TOKEN`, `CIVITAI_TOKEN`) are configured to use RunPod Secrets for maximum security.

### 🛡️ Security Highlights:
- **Checksum Validation**: All Civitai downloads are verified against official SHA256 hashes.
- **No Trace Left Behind**: The `forensic_cleanup.sh` script ensures no sensitive data persists in ephemeral storage.
- **Hardened by Default**: Secure `dockerArgs` prevent privilege escalation.

### 🧰 Technical Specifications:
- **Base Image**: `nvcr.io/nvidia/pytorch:24.04-py3`
- **Default Temp Storage**: 150 GB
EOF
)

# ─── GraphQL Definition ─────────────────────────────────────────────────────
GRAPHQL_QUERY=$(cat <<'EOF'
mutation saveTemplate($input: SaveTemplateInput!) {
  saveTemplate(input: $input) {
    id
    name
    imageName
  }
}
EOF
)

# ─── API Payload Construction ───────────────────────────────────────────────
# Build the final JSON payload using jq for safety and correctness.
PAYLOAD=$(jq -n \
  --arg name "$TEMPLATE_NAME" \
  --arg imageName "$IMAGE_NAME" \
  --argjson cDisk 150 \
  --argjson vGb 0 \
  --arg vPath "/runpod-volume" \
  --arg dArgs "--security-opt=no-new-privileges --cap-drop=ALL --dns=8.8.8.8 --dns=1.1.1.1" \
  --arg ports "8188/http,8080/http" \
  --arg readme "$README_CONTENT" \
  --arg query "$GRAPHQL_QUERY" \
  '{
    "query": $query,
    "variables": {
      "input": {
        "name": $name,
        "imageName": $imageName,
        "containerDiskInGb": $cDisk,
        "volumeInGb": $vGb,
        "volumeMountPath": $vPath,
        "dockerArgs": $dArgs,
        "ports": $ports,
        "readme": $readme,
        "env": [
          { "key": "DEBUG_MODE", "value": "true" },
          { "key": "USE_VOLUME", "value": "false" },
          { "key": "PARANOID_MODE", "value": "false" },
          { "key": "COMFY_CUSTOM_NODE_GIT_URLS", "value": "*" },
          { "key": "EXTRA_PYTHON_PACKAGES", "value": "*" },
          { "key": "FB_USERNAME", "value": "admin" },
          { "key": "FB_PASSWORD", "value": "{{ RUNPOD_SECRET_FILEBROWSER_PASSWORD }}" },
          { "key": "HUGGINGFACE_TOKEN", "value": "{{ RUNPOD_SECRET_huggingface.co }}" },
          { "key": "CIVITAI_TOKEN", "value": "{{ RUNPOD_SECRET_civitai.com }}" },
          { "key": "HF_REPOS_TO_DOWNLOAD", "value": "black-forest-labs/FLUX.1-dev" },
          { "key": "CIVITAI_CHECKPOINTS_TO_DOWNLOAD", "value": "1569593,919063,450105" },
          { "key": "CIVITAI_LORAS_TO_DOWNLOAD", "value": "182404,445135,871108" },
          { "key": "CIVITAI_VAES_TO_DOWNLOAD", "value": "1674314" }
        ]
      }
    }
  }')

# ─── API Request ────────────────────────────────────────────────────────────
echo "🚀 Sending request to create/update RunPod template..."
echo "   Template Name: $TEMPLATE_NAME"
echo "   Docker Image:  $IMAGE_NAME"

response=$(curl -s -w "\n%{http_code}" \
  -X POST "https://api.runpod.io/graphql" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
  -H "User-Agent: Project-Phoenix-Deploy/1.1" \
  -d "$PAYLOAD")

# ─── Response Handling ──────────────────────────────────────────────────────
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -ne 200 ]; then
  echo "❌ HTTP $http_code returned from RunPod API." >&2
  echo "$body" | jq . >&2
  exit 1
fi

template_id=$(echo "$body" | jq -r '.data.saveTemplate.id')
if [ -z "$template_id" ] || [ "$template_id" = "null" ]; then
  echo "❌ Error: Template creation failed. Response from API:" >&2
  echo "$body" | jq . >&2
  exit 1
fi

echo "✅ Template '$TEMPLATE_NAME' created/updated successfully!"
echo "   ID: $template_id"
echo "🎉 You can now find your template in the RunPod console."
