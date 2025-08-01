#!/bin/bash

# ==================================================================================
# PHOENIX: NO-FAIL ENTRYPOINT (TESTING MODE)
# ==================================================================================
# This version ensures the container stays running even when components fail,
# allowing for easier debugging and testing.

# --- Basic Safety Setup ---
set -euo pipefail
umask 077

# Disable core dumps
ulimit -c 0

### DEBUG: integrity_check.sh START
# Add this function to entrypoint.sh and call it after organizer.

verify_model_organization() {
    echo "🔍 [INTEGRITY] Starting post-organization integrity check..."
    
    # Count files by location
    local downloads_count=0
    local models_count=0
    local total_size_downloads="0"
    local total_size_models="0"
    
    if [ -d "/workspace/downloads_tmp" ]; then
        downloads_count=$(find /workspace/downloads_tmp -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" | wc -l)
        total_size_downloads=$(du -sb /workspace/downloads_tmp 2>/dev/null | cut -f1 || echo "0")
    fi
    
    if [ -d "/workspace/models" ]; then
        models_count=$(find /workspace/models -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" | wc -l)
        total_size_models=$(du -sb /workspace/models 2>/dev/null | cut -f1 || echo "0")
    fi
    
    echo "🔍 [INTEGRITY] Files remaining in downloads_tmp: ${downloads_count}"
    echo "🔍 [INTEGRITY] Files organized in /workspace/models: ${models_count}"
    echo "🔍 [INTEGRITY] Size in downloads_tmp: $(numfmt --to=iec ${total_size_downloads})"
    echo "🔍 [INTEGRITY] Size in models: $(numfmt --to=iec ${total_size_models})"
    
    # Check FileBrowser accessibility
    if [ -d "/workspace/models" ]; then
        echo "🔍 [INTEGRITY] FileBrowser will serve files from: /workspace"
        echo "🔍 [INTEGRITY] Models should be visible at: /workspace/models/"
        
        # Test if a sample file is readable
        local sample_file=$(find /workspace/models -name "*.safetensors" -type f | head -1)
        if [ -n "$sample_file" ]; then
            if [ -r "$sample_file" ]; then
                echo "🔍 [INTEGRITY] ✅ Sample file is readable: $(basename "$sample_file")"
            else
                echo "🔍 [INTEGRITY] ❌ Sample file is NOT readable: $(basename "$sample_file")"
                ls -la "$sample_file"
            fi
        fi
    fi
    
    # Summary
    if [ "$models_count" -gt 0 ]; then
        echo "🔍 [INTEGRITY] ✅ SUCCESS: ${models_count} model files organized successfully"
    else
        echo "🔍 [INTEGRITY] ❌ WARNING: No model files found in final location"
        echo "🔍 [INTEGRITY] This suggests an issue with the organization process"
    fi
    
    # Show directory structure for debugging
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        echo "🔍 [INTEGRITY] Final directory structure:"
        find /workspace/models -type f 2>/dev/null | head -10 | while read -r file; do
            echo "🔍 [INTEGRITY]   $(ls -la "$file")"
        done
    fi
}

# Add this call to your main() function after the organizer step:
# verify_model_organization
### DEBUG: integrity_check.sh END

### DEBUG: file_monitor_script.sh START
# Add this function to entrypoint.sh

monitor_file_system() {
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        echo "🔍 [FILE-MONITOR] Starting file system monitoring..."
        
        # Create a background monitor that runs during organization
        (
            while true; do
                sleep 5
                echo "🔍 [FILE-MONITOR] $(date '+%H:%M:%S') - .safetensors count:"
                echo "🔍 [FILE-MONITOR]   /workspace/downloads_tmp: $(find /workspace/downloads_tmp -name "*.safetensors" 2>/dev/null | wc -l) files"
                echo "🔍 [FILE-MONITOR]   /workspace/models: $(find /workspace/models -name "*.safetensors" 2>/dev/null | wc -l) files"
                
                # Check if organizer is still running
                if ! pgrep -f "organizer.sh" > /dev/null; then
                    echo "🔍 [FILE-MONITOR] Organizer finished, stopping monitor"
                    break
                fi
            done
        ) &
        
        # Store the PID so we can kill it later
        echo $! > /tmp/file_monitor.pid
    fi
}

# Add this to your main() function before step 3:
main() {
    echo "🚀 Phoenix Entrypoint: Initializing container..."
    
    # ... existing steps 1 & 2 ...
    
    # Start file monitoring before organizer
    monitor_file_system
    
    echo "  -> 3/4: Running File Organizer..."
    source "${SCRIPT_DIR}/organizer.sh"
    
    # Kill the monitor after organizer completes
    if [ -f "/tmp/file_monitor.pid" ]; then
        kill $(cat /tmp/file_monitor.pid) 2>/dev/null || true
        rm -f /tmp/file_monitor.pid
    fi
    
    # ... rest of main function
}
### DEBUG: file_monitor_script.sh END

# --- Cleanup Function (Non-Destructive in Testing Mode) ---
cleanup() {
    echo "🚨 Phoenix Entrypoint: Received exit signal..."
    
    # In testing mode, we do minimal cleanup to preserve debugging info
    if [ "${PARANOID_MODE:-false}" = "true" ]; then
        echo "  PARANOID_MODE enabled - performing full cleanup"
        if [ -x "/usr/local/bin/scripts/forensic_cleanup.sh" ]; then
            /usr/local/bin/scripts/forensic_cleanup.sh
        fi
    else
        echo "  Testing mode - preserving data for debugging"
        # Only clean temporary sensitive data, keep everything else
        rm -rf /tmp/* 2>/dev/null || true
        unset HUGGINGFACE_TOKEN CIVITAI_TOKEN 2>/dev/null || true
    fi
    
    echo "✅ Phoenix Entrypoint: Cleanup finished."
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup SIGINT SIGTERM EXIT

# --- Component Runner (Failure-Tolerant) ---
run_component() {
    local component_name="$1"
    local script_path="$2"
    local required="${3:-false}"
    
    echo "  -> Running ${component_name}..."
    
    if [ ! -f "$script_path" ]; then
        echo "     ❌ Script not found: $script_path"
        if [ "$required" = "true" ]; then
            echo "     This is a required component - cannot continue"
            return 1
        else
            echo "     This is optional - continuing"
            return 0
        fi
    fi
    
    if [ ! -x "$script_path" ]; then
        echo "     ⚠️ Script not executable: $script_path (attempting to fix)"
        chmod +x "$script_path" || true
    fi
    
    # Run the script and capture its exit code
    local exit_code=0
    if ! source "$script_path"; then
        exit_code=$?
        echo "     ❌ ${component_name} failed with exit code: $exit_code"
        
        if [ "$required" = "true" ]; then
            echo "     This is a required component - cannot continue"
            return $exit_code
        else
            echo "     This is optional - continuing despite failure"
            return 0
        fi
    else
        echo "     ✅ ${component_name} completed successfully"
        return 0
    fi
}

# --- Service Health Check ---
check_service_health() {
    local service_name="$1"
    local port="$2"
    local max_attempts="${3:-30}"
    
    echo "  Checking ${service_name} health on port ${port}..."
    
    for attempt in $(seq 1 $max_attempts); do
        if curl -s -f "http://127.0.0.1:${port}" >/dev/null 2>&1; then
            echo "  ✅ ${service_name} is responding on port ${port}"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            echo "  ⚠️ ${service_name} not responding after ${max_attempts} attempts"
            return 1
        fi
        
        sleep 2
    done
}

# --- Network Health Check ---
check_network() {
    local max_attempts=10
    local attempt=1
    local wait_time=3
    
    echo "🌐 Checking network connectivity..."
    
    while [ $attempt -le $max_attempts ]; do
        echo "  -> Attempt $attempt/$max_attempts: Testing connectivity..."
        
        # Test multiple methods for more reliable detection
        local dns_test=false
        local http_test=false
        
        # Method 1: DNS resolution test (multiple servers)
        if nslookup google.com 8.8.8.8 >/dev/null 2>&1 || \
           nslookup cloudflare.com 1.1.1.1 >/dev/null 2>&1; then
            dns_test=true
        fi
        
        # Method 2: HTTP connectivity test (with timeout)
        if timeout 5 curl -s --max-time 5 https://www.google.com >/dev/null 2>&1 || \
           timeout 5 curl -s --max-time 5 https://httpbin.org/ip >/dev/null 2>&1; then
            http_test=true
        fi
        
        # Success if either method works
        if [ "$dns_test" = true ] || [ "$http_test" = true ]; then
            echo "✅ Network connectivity confirmed (DNS: $dns_test, HTTP: $http_test)"
            return 0
        fi
        
        echo "❌ Network not ready (DNS: $dns_test, HTTP: $http_test)"
        
        if [ $attempt -eq $max_attempts ]; then
            echo "⚠️  Network wait exhausted after $max_attempts attempts"
            echo "   Proceeding anyway - downloads may work due to retry logic"
            return 1
        fi
        
        echo "   Waiting ${wait_time}s before retry..."
        sleep $wait_time
        
        # Exponential backoff (cap at 10s)
        wait_time=$((wait_time < 10 ? wait_time + 2 : 10))
        attempt=$((attempt + 1))
    done
}

# --- Main Orchestration ---
main() {
    echo "🚀 Phoenix Entrypoint: Starting in NO-FAIL testing mode..."
    echo "   Container will continue running even if some components fail"
    echo "   Set PARANOID_MODE=true for full cleanup on exit"
    
    # Define script paths
    local SCRIPT_DIR="/usr/local/bin/scripts"
    local total_errors=0
    
    echo ""
    echo "=== PHOENIX STARTUP SEQUENCE ==="
    
    # Step 1: System Setup (REQUIRED - must succeed)
    if ! run_component "System Setup" "${SCRIPT_DIR}/system_setup.sh" "true"; then
        echo "❌ FATAL: System setup failed - cannot continue"
        exit 1
    fi
    
    # Step 1.5: Network Check
    if ! check_network; then
        echo "⚠️ Network check failed, but continuing in NO-FAIL mode."
        # In a production entrypoint, you would likely 'exit 1' here.
    fi

    # Step 2: Download Manager (OPTIONAL - failures are acceptable)
    if ! run_component "Download Manager" "${SCRIPT_DIR}/download_manager.sh" "false"; then
        echo "⚠️ Download manager had issues - continuing anyway"
        total_errors=$((total_errors + 1))
    fi
    
    # Step 3: File Organizer (OPTIONAL - only runs if downloads exist)
    if [ -d "${DOWNLOAD_TMP_DIR:-/workspace/downloads_tmp}" ] && [ "$(ls -A "${DOWNLOAD_TMP_DIR:-/workspace/downloads_tmp}" 2>/dev/null)" ]; then
        if ! run_component "File Organizer" "${SCRIPT_DIR}/organizer.sh" "false"; then
            echo "⚠️ File organizer had issues - continuing anyway"
            total_errors=$((total_errors + 1))
        fi
        verify_model_organization
        monitor_file_system &
    else
        echo "  -> File Organizer: Skipped (no downloads to organize)"
    fi
    
    # Step 4: Service Manager (SEMI-REQUIRED - container is less useful without it)
    if ! run_component "Service Manager" "${SCRIPT_DIR}/service_manager.sh" "false"; then
        echo "⚠️ Service manager had issues - some services may not be available"
        total_errors=$((total_errors + 1))
    fi
    
    echo ""
    echo "=== STARTUP COMPLETE ==="
    
    if [ $total_errors -eq 0 ]; then
        echo "✅ All components started successfully!"
    else
        echo "⚠️ Startup completed with ${total_errors} component(s) having issues"
        echo "   Container is running but some features may be limited"
    fi
    
    echo ""
    echo "📊 Service Status Check..."
    
    # Wait a moment for services to start
    sleep 5
    
    # Check service health
    local service_issues=0
    
    if ! check_service_health "ComfyUI" "8188" 15; then
        service_issues=$((service_issues + 1))
        echo "  ℹ️ ComfyUI may still be starting up - check logs for details"
    fi
    
    if ! check_service_health "FileBrowser" "8080" 10; then
        service_issues=$((service_issues + 1))
        echo "  ℹ️ FileBrowser may not be running - check configuration"
    fi
    
    echo ""
    echo "🎯 Container Status Summary:"
    echo "   📍 Storage Root: ${STORAGE_ROOT:-/workspace}"
    echo "   🔧 Debug Mode: ${DEBUG_MODE:-false}"
    echo "   🛡️ Paranoid Mode: ${PARANOID_MODE:-false}"
    echo "   🎮 GPU Available: ${GPU_AVAILABLE:-unknown}"
    
    if [ -n "${GPU_NAME:-}" ] && [ "${GPU_NAME}" != "CPU_MODE" ]; then
        echo "   🖥️ GPU: ${GPU_NAME} (${GPU_MEMORY:-0}MiB VRAM)"
    fi
    
    echo ""
    if [ $service_issues -eq 0 ]; then
        echo "🚀 All services appear to be running!"
        echo "   • ComfyUI: http://localhost:8188"
        echo "   • FileBrowser: http://localhost:8080"
    else
        echo "⚠️ Some services may have issues - check individual service logs"
    fi
    
    echo ""
    echo "📝 Troubleshooting Tips:"
    echo "   • Set DEBUG_MODE=true for verbose logging"
    echo "   • Check /workspace/models/ for downloaded files"
    echo "   • Ensure tokens are properly configured for private models"
    echo "   • Use FileBrowser to inspect directory contents"
    
    echo ""
    echo "🔄 Container will now wait indefinitely..."
    echo "   Use Ctrl+C or docker stop to gracefully shutdown"
    
    # Enhanced wait loop with periodic status updates
    local wait_minutes=0
    while true; do
        sleep 300  # 5 minutes
        wait_minutes=$((wait_minutes + 5))
        
        if [ "${DEBUG_MODE:-false}" = "true" ]; then
            echo "⏰ Container running for ${wait_minutes} minutes..."
            
            # Periodic health checks in debug mode
            if [ $((wait_minutes % 15)) -eq 0 ]; then
                echo "🏥 Periodic health check..."
                check_service_health "ComfyUI" "8188" 3 || echo "  ComfyUI may need attention"
                check_service_health "FileBrowser" "8080" 3 || echo "  FileBrowser may need attention"
            fi
        fi
        
        # Optional: periodic cleanup of temp files (but preserve debugging info)
        if [ $((wait_minutes % 60)) -eq 0 ]; then  # Every hour
            find /tmp -name "*.tmp" -mmin +30 -delete 2>/dev/null || true
        fi
    done
}

# Execute the main function
main