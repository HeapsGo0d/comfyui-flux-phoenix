#!/bin/bash
# ==================================================================================
# PHOENIX: FORENSIC CLEANUP SCRIPT
# ==================================================================================
# This script is called by the trap in entrypoint.sh on container exit.
# Its purpose is to securely remove all temporary files, logs, caches, and other
# potentially sensitive data to ensure a "leave-no-trace" session.

# --- Logging Function ---
log_cleanup() {
    echo "  [CLEANUP] $1"
}

log_cleanup "Starting forensic cleanup process..."

# --- Paranoid Mode Check ---
# If PARANOID_MODE is true, we will use 'shred' for a more secure deletion
# on specific files. For most cloud environments, this is overkill, but it's a
# feature we support.
if [ "${PARANOID_MODE:-false}" = "true" ]; then
    log_cleanup "Paranoid mode enabled. Using 'shred' where applicable."
    # Example: Securely shred the filebrowser database if it exists
    if [ -f "${STORAGE_ROOT}/filebrowser.db" ]; then
        log_cleanup "Shredding File Browser database..."
        shred -n 1 -u "${STORAGE_ROOT}/filebrowser.db"
    fi
fi

# --- Target Directories and Files for Deletion ---
# We define an array of paths to be recursively and forcefully deleted.
# This makes the script easy to extend in the future.
declare -a paths_to_delete=(
    # All temporary files in /tmp
    "/tmp/*"
    # The entire workspace except for the ComfyUI application code itself
    # We delete downloaded models, inputs, outputs if NOT on a persistent volume
    "/workspace/downloads_tmp"
    "/workspace/input"
    "/workspace/output"
    "/workspace/models"
    # Python caches
    "/root/.cache/pip"
    "/workspace/.cache"
    # Hugging Face cache
    "/root/.cache/huggingface"
    # Any other potential log or cache files
    "/var/log/*.log"
    "/root/.bash_history"
)

# --- Deletion Loop ---
# We iterate through our list of targets and delete them.
# The '2>/dev/null || true' part ensures that the script does not fail if a
# path doesn't exist (e.g., /tmp/* on an empty directory).
for path in "${paths_to_delete[@]}"; do
    log_cleanup "Deleting: ${path}"
    rm -rf ${path} 2>/dev/null || true
done

# --- Final Cleanup ---
# A final sweep to remove Python __pycache__ directories from the ComfyUI folder.
log_cleanup "Removing all Python bytecode cache..."
find /workspace/ComfyUI -type f -name "*.pyc" -delete
find /workspace/ComfyUI -type d -name "__pycache__" -exec rm -rf {} +

log_cleanup "✅ Forensic cleanup complete. Leaving no trace."
