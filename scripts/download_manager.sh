#!/bin/bash
# ==================================================================================
# PHOENIX: DOWNLOAD MANAGER WRAPPER (PYTHON-BASED)
# ==================================================================================
# This script is sourced by entrypoint.sh. It calls our Python downloader.

# --- Logging Function ---
log_download() {
    echo "  [DOWNLOAD] $1"
}

log_download "Initializing Python-based download manager..."

# Call the Python download manager
python3 /usr/local/bin/scripts/phoenix_downloader.py

# Check if Python script succeeded
if [ $? -eq 0 ]; then
    log_download "Python download manager completed successfully."
else
    log_download "❌ Python download manager encountered errors."
    log_download "⏭️ Continuing with startup process..."
fi