#!/bin/bash

# ==================================================================================
# SECTION 1: ROBUST SCRIPTING PRACTICES
# ==================================================================================
# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# The return value of a pipeline is the status of the last command to exit with a
# non-zero status, or zero if no command failed.
set -euo pipefail
# Disable core dumps to prevent memory from being written to disk on crash.
ulimit -c 0
# ==================================================================================
# SECTION 2: SIGNAL TRAPPING
# ==================================================================================
# This function is called when the script receives a signal to exit.
# It ensures that our cleanup script is always called, allowing us to perform
# forensic cleanup of sensitive data, as defined in our requirements.
cleanup() {
    echo "🚨 Phoenix Entrypoint: Received exit signal. Initiating cleanup..."
    # Call the forensic cleanup script. Check if it exists and is executable.
    if [ -x "/usr/local/bin/scripts/forensic_cleanup.sh" ]; then
        /usr/local/bin/scripts/forensic_cleanup.sh
    else
        echo "⚠️ Cleanup script not found or not executable. Skipping."
    fi
    echo "✅ Phoenix Entrypoint: Cleanup finished."
    exit 0
}

# Trap signals for graceful shutdown.
# SIGINT: Sent on Ctrl+C.
# SIGTERM: Sent by 'docker stop'.
# EXIT: Always runs when the script exits, regardless of the reason.
trap cleanup SIGINT SIGTERM EXIT

# ==================================================================================
# SECTION 3: ORCHESTRATION
# =================================S=================================================
# The main function that orchestrates the entire startup sequence.
main() {
    echo "🚀 Phoenix Entrypoint: Initializing container..."

    # Define paths to our helper scripts for clarity.
    local SCRIPT_DIR="/usr/local/bin/scripts"

    # Step 1: Perform initial system setup and validation.
    # This script will check for GPUs, disk space, and other prerequisites.
    echo "  -> 1/4: Running System Setup..."
    source "${SCRIPT_DIR}/system_setup.sh"

    # Step 2: Handle all model and file downloads.
    # This script will use aria2c to download from Hugging Face, Civitai, etc.
    echo "  -> 2/4: Running Download Manager..."
    source "${SCRIPT_DIR}/download_manager.sh"

    # Step 3: Organize the downloaded files into their correct locations.
    # This script will move models, LoRAs, etc., into the correct ComfyUI folders.
    echo "  -> 3/4: Running File Organizer..."
    source "${SCRIPT_DIR}/organizer.sh"

    # Step 4: Launch the main application services.
    # This script will start ComfyUI and the File Browser in the background.
    echo "  -> 4/4: Running Service Manager..."
    source "${SCRIPT_DIR}/service_manager.sh"

    echo "✅ Phoenix Entrypoint: All startup scripts completed. Services are running."
    echo "   ComfyUI should be available on port 8188."

    # This 'wait' command is crucial. It tells the script to wait indefinitely for
    # all background processes (started by service_manager.sh) to exit.
    # The 'trap' will handle the cleanup when the container is stopped.
    wait
}

# Execute the main function to start the sequence.
main