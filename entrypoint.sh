#!/bin/bash

# ==================================================================================
# PHOENIX: ENHANCED ENTRYPOINT WITH DIAGNOSTIC INTEGRATION
# ==================================================================================
# This version includes better error handling and diagnostic capabilities

# --- Basic Safety Setup ---
set -euo pipefail
umask 077

# Disable core dumps
ulimit -c 0

# --- Enhanced Cleanup Function ---
cleanup() {
    echo "🚨 Phoenix Entrypoint: Received exit signal..."
    
    # Show brief system state before cleanup
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        echo "  Final system state:"
        echo "    Models organized: $(find "${STORAGE_ROOT:-/workspace}/models" -name "*.safetensors" -o -name "*.ckpt" 2>/dev/null | wc -l) files"
        echo "    Downloads remaining: $(find "/workspace/downloads_tmp" -name "*.safetensors" -o -name "*.ckpt" 2>/dev/null | wc -l) files"
    fi
    
    if [ "${PARANOID_MODE:-false}" = "true" ]; then
        echo "  PARANOID_MODE enabled - performing full cleanup"
        if [ -x "/usr/local/bin/scripts/forensic_cleanup.sh" ]; then
            /usr/local/bin/scripts/forensic_cleanup.sh
        fi
    else
        echo "  Standard cleanup - preserving data for debugging"
        rm -rf /tmp/* 2>/dev/null || true
        unset HUGGINGFACE_TOKEN CIVITAI_TOKEN 2>/dev/null || true
    fi
    
    echo "✅ Phoenix Entrypoint: Cleanup finished."
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup SIGINT SIGTERM EXIT

# --- Enhanced Component Runner ---
run_component() {
    local component_name="$1"
    local script_path="$2"
    local required="${3:-false}"
    local timeout="${4:-300}"  # 5 minute default timeout
    
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
    
    # Run with timeout to prevent hanging
    local exit_code=0
    echo "     Starting ${component_name} (timeout: ${timeout}s)..."
    
    if timeout "$timeout" bash -c "source '$script_path'"; then
        echo "     ✅ ${component_name} completed successfully"
        return 0
    else
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "     ❌ ${component_name} timed out after ${timeout}s"
        else
            echo "     ❌ ${component_name} failed with exit code: $exit_code"
        fi
        
        if [ "$required" = "true" ]; then
            echo "     This is a required component - cannot continue"
            return $exit_code
        else
            echo "     This is optional - continuing despite failure"
            return 0
        fi
    fi
}

# --- Enhanced Service Health Check ---
check_service_health() {
    local service_name="$1"
    local port="$2"
    local max_attempts="${3:-30}"
    
    echo "  Checking ${service_name} health on port ${port}..."
    
    for attempt in $(seq 1 $max_attempts); do
        if curl -s --connect-timeout 5 --max-time 10 -f "http://127.0.0.1:${port}" >/dev/null 2>&1; then
            echo "  ✅ ${service_name} is responding on port ${port}"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            echo "  ⚠️ ${service_name} not responding after ${max_attempts} attempts"
            return 1
        fi
        
        # Show progress for long waits
        if [ $attempt -eq 10 ] || [ $attempt -eq 20 ]; then
            echo "    Still waiting for ${service_name}... (attempt $attempt/$max_attempts)"
        fi
        
        sleep 2
    done
}

# --- Enhanced Network Check ---
check_network() {
    local max_attempts=10
    local attempt=1
    local wait_time=3
    
    echo "🌐 Checking network connectivity..."
    
    while [ $attempt -le $max_attempts ]; do
        echo "  -> Attempt $attempt/$max_attempts: Testing connectivity..."
        
        local dns_test=false
        local http_test=false
        
        # Test DNS resolution (multiple servers)
        if timeout 10 nslookup google.com 8.8.8.8 >/dev/null 2>&1 || \
           timeout 10 nslookup cloudflare.com 1.1.1.1 >/dev/null 2>&1; then
            dns_test=true
        fi
        
        # Test HTTP connectivity with timeout
        if timeout 10 curl -s --max-time 5 https://www.google.com >/dev/null 2>&1 || \
           timeout 10 curl -s --max-time 5 https://httpbin.org/ip >/dev/null 2>&1; then
            http_test=true
        fi
        
        if [ "$dns_test" = true ] || [ "$http_test" = true ]; then
            echo "✅ Network connectivity confirmed (DNS: $dns_test, HTTP: $http_test)"
            return 0
        fi
        
        echo "❌ Network not ready (DNS: $dns_test, HTTP: $http_test)"
        
        if [ $attempt -eq $max_attempts ]; then
            echo "⚠️ Network wait exhausted after $max_attempts attempts"
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

# --- Post-Organization Verification ---
verify_organization_results() {
    echo "🔍 Verifying file organization results..."
    
    # Use the enhanced integrity check
    if [ -f "/usr/local/bin/scripts/enhanced_integrity_check.sh" ]; then
        chmod +x /usr/local/bin/scripts/enhanced_integrity_check.sh
        /usr/local/bin/scripts/enhanced_integrity_check.sh
        return $?
    else
        # Fallback basic check
        local models_count=0
        local downloads_count=0
        
        if [ -d "${STORAGE_ROOT:-/workspace}/models" ]; then
            models_count=$(find "${STORAGE_ROOT:-/workspace}/models" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" | wc -l)
        fi
        
        if [ -d "/workspace/downloads_tmp" ]; then
            downloads_count=$(find "/workspace/downloads_tmp" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" | wc -l)
        fi
        
        echo "🔍 Basic verification: $models_count models organized, $downloads_count remain in downloads"
        
        if [ "$models_count" -gt 0 ]; then
            echo "✅ Organization appears successful"
            return 0
        elif [ "$downloads_count" -gt 0 ]; then
            echo "⚠️ Files exist but weren't organized properly"
            return 1
        else
            echo "❌ No model files found anywhere"
            return 1
        fi
    fi
}

# --- Emergency Recovery Mode ---
emergency_recovery() {
    echo "🚑 EMERGENCY RECOVERY: Attempting to salvage stranded files..."
    
    local downloads_tmp="/workspace/downloads_tmp"
    local models_dir="${STORAGE_ROOT:-/workspace}/models"
    
    if [ -d "$downloads_tmp" ]; then
        local stranded_files
        stranded_files=$(find "$downloads_tmp" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" | wc -l)
        
        if [ "$stranded_files" -gt 0 ]; then
            echo "🚑 Found $stranded_files stranded files - attempting emergency move..."
            
            # Create emergency checkpoint directory
            mkdir -p "$models_dir/checkpoints" 2>/dev/null || true
            
            # Simple move operation
            local recovered=0
            find "$downloads_tmp" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" | while read -r file; do
                local filename=$(basename "$file")
                if mv "$file" "$models_dir/checkpoints/$filename" 2>/dev/null; then
                    echo "🚑 Recovered: $filename"
                    ((recovered++))
                fi
            done
            
            echo "🚑 Emergency recovery completed - check models/checkpoints/ directory"
            return 0
        fi
    fi
    
    echo "🚑 No files found for emergency recovery"
    return 1
}

# --- Main Orchestration ---
main() {
    echo "🚀 Phoenix Entrypoint: Starting enhanced container initialization..."
    echo "   Version: Enhanced with diagnostics and atomic operations"
    echo "   Mode: Production with fallback recovery"
    
    # Define script paths
    local SCRIPT_DIR="/usr/local/bin/scripts"
    local total_errors=0
    local critical_failure=false
    
    echo ""
    echo "=== PHOENIX STARTUP SEQUENCE ==="
    
    # Step 1: System Setup (REQUIRED - must succeed)
    echo ""
    echo "📋 Step 1: System Setup"
    if ! run_component "System Setup" "${SCRIPT_DIR}/system_setup.sh" "true" 60; then
        echo "❌ FATAL: System setup failed - cannot continue"
        
        # Run diagnostics before exit
        if [ -f "${SCRIPT_DIR}/diagnosis.sh" ]; then
            echo "🔍 Running diagnostics before exit..."
            chmod +x "${SCRIPT_DIR}/diagnosis.sh"
            "${SCRIPT_DIR}/diagnosis.sh"
        fi
        
        exit 1
    fi
    
    # Step 2: Network Check
    echo ""
    echo "🌐 Step 2: Network Connectivity"
    if ! check_network; then
        echo "⚠️ Network issues detected - downloads may fail"
        total_errors=$((total_errors + 1))
    fi

    # Step 3: Download Manager
    echo ""
    echo "📥 Step 3: Download Manager"
    if ! run_component "Download Manager" "${SCRIPT_DIR}/download_manager.sh" "false" 1800; then  # 30 min timeout
        echo "⚠️ Download manager had issues - continuing anyway"
        total_errors=$((total_errors + 1))
    fi
    
    # Step 4: File Organization (Critical for functionality)
    echo ""
    echo "📂 Step 4: File Organization"
    local organization_success=true
    
    if [ -d "/workspace/downloads_tmp" ] && [ "$(find /workspace/downloads_tmp -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" | wc -l)" -gt 0 ]; then
        echo "  Files detected in downloads_tmp - proceeding with organization..."
        
        if ! run_component "File Organizer" "${SCRIPT_DIR}/organizer.sh" "false" 600; then  # 10 min timeout
            echo "⚠️ File organizer failed - will attempt verification and recovery"
            organization_success=false
            total_errors=$((total_errors + 1))
        fi
        
        # Always verify organization results
        echo ""
        echo "🔍 Step 4.1: Organization Verification"
        if ! verify_organization_results; then
            echo "⚠️ Organization verification failed"
            organization_success=false
            
            # Attempt emergency recovery
            echo ""
            echo "🚑 Step 4.2: Emergency Recovery"
            if emergency_recovery; then
                echo "✅ Emergency recovery succeeded - some models may be available"
                organization_success=true  # Partial success
            else
                echo "❌ Emergency recovery failed - no models available"
                critical_failure=true
            fi
        else
            echo "✅ Organization verification passed"
        fi
        
    else
        echo "  No files found in downloads_tmp - skipping organization"
    fi
    
    # Step 5: Service Manager
    echo ""
    echo "🚀 Step 5: Service Manager"
    if ! run_component "Service Manager" "${SCRIPT_DIR}/service_manager.sh" "false" 120; then
        echo "⚠️ Service manager had issues - some services may not be available"
        total_errors=$((total_errors + 1))
    fi
    
    echo ""
    echo "=== STARTUP COMPLETE ==="
    
    # Startup Summary
    if [ "$critical_failure" = "true" ]; then
        echo "❌ CRITICAL FAILURE: Container started but no models are available"
        echo "   ComfyUI will not be functional for inference"
        echo "   Check logs and consider restarting with DEBUG_MODE=true"
    elif [ $total_errors -eq 0 ]; then
        echo "✅ All components started successfully!"
        echo "   Container is fully functional"
    else
        echo "⚠️ Startup completed with ${total_errors} component(s) having issues"
        echo "   Container is running but some features may be limited"
        if [ "$organization_success" = "true" ]; then
            echo "   Models are available - basic functionality should work"
        fi
    fi
    
    echo ""
    echo "📊 Service Status Check..."
    
    # Wait for services to stabilize
    sleep 5
    
    # Check service health
    local service_issues=0
    if ! check_service_health "ComfyUI"; then
        service_issues=1
    fi
    if ! check_service_health "FileBrowser"; then
        service_issues=1
    fi

    if [ "$service_issues" -ne 0 ]; then
        log "FATAL: One or more services failed to start. Entering emergency mode."
        emergency_mode "Service startup failure"
        # Emergency mode is an infinite loop, so we shouldn't get here.
        # But as a fallback, exit.
        exit 1
    fi

    log "All services are operational. System is fully initialized."
    log "-------------------------------------------------------------------"
    log "Phoenix is running. Access services at their respective ports."
    log "-------------------------------------------------------------------"

    # Keep the container running by waiting on the service manager
    wait_for_service_manager
}

# Execute the main function with all script arguments
main "$@"