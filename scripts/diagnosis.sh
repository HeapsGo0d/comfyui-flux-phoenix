#!/bin/bash
# ==================================================================================
# PHOENIX: COMPREHENSIVE DIAGNOSIS SCRIPT
# ==================================================================================
# This script helps diagnose why file organization is failing

echo "🔍 [DIAGNOSIS] Phoenix Container Diagnosis Starting..."
echo "🔍 [DIAGNOSIS] Timestamp: $(date)"
echo "🔍 [DIAGNOSIS] =============================================="

# --- Environment Information ---
echo ""
echo "📊 [ENV] Environment Variables:"
echo "📊 [ENV] STORAGE_ROOT=${STORAGE_ROOT:-not_set}"
echo "📊 [ENV] DEBUG_MODE=${DEBUG_MODE:-not_set}"
echo "📊 [ENV] USE_VOLUME=${USE_VOLUME:-not_set}"
echo "📊 [ENV] PARANOID_MODE=${PARANOID_MODE:-not_set}"
echo "📊 [ENV] Current user: $(whoami)"
echo "📊 [ENV] Current groups: $(groups)"
echo "📊 [ENV] Current umask: $(umask)"
echo "📊 [ENV] PWD: $(pwd)"

# --- Process Information ---
echo ""
echo "🔄 [PROC] Running Processes:"
echo "🔄 [PROC] Python/download processes:"
pgrep -f python3 | while read -r pid; do
    echo "🔄 [PROC]   PID $pid: $(ps -p $pid -o cmd --no-headers 2>/dev/null || echo 'process ended')"
done

echo "🔄 [PROC] Download-related processes:"
pgrep -f "aria2\|huggingface-cli\|organizer\|download" | while read -r pid; do
    echo "🔄 [PROC]   PID $pid: $(ps -p $pid -o cmd --no-headers 2>/dev/null || echo 'process ended')"
done

# --- File System Deep Dive ---
echo ""
echo "📂 [FS] File System Analysis:"

# Check all potential locations for model files
locations=(
    "/workspace"
    "/workspace/downloads_tmp"
    "/workspace/models"
    "/workspace/ComfyUI"
    "/runpod-volume"
    "/runpod-volume/models"
)

for location in "${locations[@]}"; do
    if [ -d "$location" ]; then
        echo "📂 [FS] $location:"
        echo "📂 [FS]   Exists: YES"
        echo "📂 [FS]   Readable: $([ -r "$location" ] && echo "YES" || echo "NO")"
        echo "📂 [FS]   Writable: $([ -w "$location" ] && echo "YES" || echo "NO")"
        echo "📂 [FS]   Owner: $(stat -c '%U:%G' "$location" 2>/dev/null || echo "unknown")"
        echo "📂 [FS]   Permissions: $(stat -c '%A' "$location" 2>/dev/null || echo "unknown")"
        
        # Count model files
        local model_count=0
        model_count=$(find "$location" -maxdepth 3 -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" 2>/dev/null | wc -l)
        echo "📂 [FS]   Model files: $model_count"
        
        # Show directory structure (first few items)
        echo "📂 [FS]   Contents (sample):"
        ls -la "$location" 2>/dev/null | head -8 | while read -r line; do
            echo "📂 [FS]     $line"
        done
        
        # If this is downloads_tmp, show what's actually in there
        if [[ "$location" == *"downloads_tmp"* ]] && [ "$model_count" -gt 0 ]; then
            echo "📂 [FS]   Model files in downloads_tmp:"
            find "$location" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" 2>/dev/null | head -5 | while read -r file; do
                local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
                local readable=$([ -r "$file" ] && echo "✅" || echo "❌")
                echo "📂 [FS]     $readable $(basename "$file") ($(numfmt --to=iec $size))"
            done
        fi
    else
        echo "📂 [FS] $location: Does not exist"
    fi
    echo ""
done

# --- Symlink Analysis ---
echo "🔗 [SYMLINK] Symlink Analysis:"
comfyui_links=("/workspace/ComfyUI/models" "/workspace/ComfyUI/input" "/workspace/ComfyUI/output")

for link in "${comfyui_links[@]}"; do
    if [ -L "$link" ]; then
        local target=$(readlink "$link")
        echo "🔗 [SYMLINK] $link → $target"
        echo "🔗 [SYMLINK]   Link exists: YES"
        echo "🔗 [SYMLINK]   Target exists: $([ -d "$target" ] && echo "YES" || echo "NO")"
        echo "🔗 [SYMLINK]   Target readable: $([ -r "$target" ] && echo "YES" || echo "NO")"
    elif [ -e "$link" ]; then
        echo "🔗 [SYMLINK] $link: Regular directory (not symlink)"
    else
        echo "🔗 [SYMLINK] $link: Does not exist"
    fi
done

# --- Download Analysis ---
echo ""
echo "📥 [DOWNLOAD] Download Analysis:"

# Check for download artifacts
download_artifacts=(
    "/workspace/downloads_tmp"
    "/tmp/files_to_organize.txt"
    "/workspace/.aria2"
    "/root/.cache/huggingface"
)

for artifact in "${download_artifacts[@]}"; do
    if [ -e "$artifact" ]; then
        if [ -d "$artifact" ]; then
            local count=$(find "$artifact" -type f 2>/dev/null | wc -l)
            echo "📥 [DOWNLOAD] $artifact: Directory with $count files"
        else
            local size=$(stat -c%s "$artifact" 2>/dev/null || echo "0")
            echo "📥 [DOWNLOAD] $artifact: File ($(numfmt --to=iec $size))"
        fi
    else
        echo "📥 [DOWNLOAD] $artifact: Not found"
    fi
done

# Check for aria2 segment files (indicates interrupted downloads)
aria2_files=$(find /workspace /tmp -name "*.aria2" 2>/dev/null | wc -l)
echo "📥 [DOWNLOAD] Active aria2 downloads: $aria2_files"

# --- Permissions Deep Dive ---
echo ""
echo "🔐 [PERM] Permissions Deep Dive:"

# Test ability to create files in key locations
test_locations=("${STORAGE_ROOT:-/workspace}" "/workspace" "/workspace/models")

for test_dir in "${test_locations[@]}"; do
    if [ -d "$test_dir" ]; then
        local test_file="${test_dir}/.write_test_$$"
        if touch "$test_file" 2>/dev/null; then
            echo "🔐 [PERM] $test_dir: Write test PASSED ✅"
            rm -f "$test_file" 2>/dev/null
        else
            echo "🔐 [PERM] $test_dir: Write test FAILED ❌"
            echo "🔐 [PERM]   Directory owner: $(stat -c '%U:%G' "$test_dir" 2>/dev/null || echo "unknown")"
            echo "🔐 [PERM]   Directory perms: $(stat -c '%A' "$test_dir" 2>/dev/null || echo "unknown")"
        fi
    else
        echo "🔐 [PERM] $test_dir: Directory does not exist"
    fi
done

# Test atomic operations (critical for organizer)
echo "🔐 [PERM] Testing atomic operations:"
test_source="/tmp/atomic_test_source_$$"
test_dest_dir="${STORAGE_ROOT:-/workspace}/models/checkpoints"
test_dest="$test_dest_dir/atomic_test_dest_$$"

# Create test file
if echo "test content" > "$test_source" 2>/dev/null; then
    if [ -d "$test_dest_dir" ]; then
        # Test move operation
        if mv "$test_source" "$test_dest" 2>/dev/null; then
            echo "🔐 [PERM] Atomic move operation: PASSED ✅"
            rm -f "$test_dest" 2>/dev/null
        else
            echo "🔐 [PERM] Atomic move operation: FAILED ❌"
            echo "🔐 [PERM]   This explains organizer failures!"
            rm -f "$test_source" 2>/dev/null
        fi
    else
        echo "🔐 [PERM] Destination directory missing: $test_dest_dir"
        rm -f "$test_source" 2>/dev/null
    fi
else
    echo "🔐 [PERM] Cannot create test file in /tmp"
fi

# --- Space Analysis ---
echo ""
echo "💾 [SPACE] Disk Space Analysis:"
df -h | grep -E "(Filesystem|/workspace|/runpod|/tmp)" | while read -r line; do
    echo "💾 [SPACE] $line"
done

# Check if we're running out of inodes
echo "💾 [SPACE] Inode usage:"
df -i | grep -E "(Filesystem|/workspace|/runpod|/tmp)" | head -4 | while read -r line; do
    echo "💾 [SPACE] $line"
done

# --- Service Analysis ---
echo ""
echo "🚀 [SERVICE] Service Analysis:"

# Check if services are running
services=("ComfyUI:8188" "FileBrowser:8080")
for service in "${services[@]}"; do
    local name=${service%:*}
    local port=${service#*:}
    
    if curl -s --connect-timeout 3 "http://localhost:$port" >/dev/null 2>&1; then
        echo "🚀 [SERVICE] $name (port $port): RUNNING ✅"
    else
        echo "🚀 [SERVICE] $name (port $port): NOT RESPONDING ❌"
        
        # Check if process exists
        if pgrep -f "$name" >/dev/null 2>&1; then
            echo "🚀 [SERVICE]   Process exists but not responding"
        else
            echo "🚀 [SERVICE]   Process not running"
        fi
    fi
done

# --- Log Analysis ---
echo ""
echo "📋 [LOG] Recent Log Analysis:"

# Look for recent error patterns in logs
echo "📋 [LOG] Searching for recent errors..."

# Check system logs for relevant errors (if accessible)
if [ -r "/var/log/syslog" ]; then
    echo "📋 [LOG] Recent system errors:"
    tail -20 /var/log/syslog 2>/dev/null | grep -i "error\|fail\|denied" | tail -5 | while read -r line; do
        echo "📋 [LOG]   $line"
    done
fi

# Check for Python errors
if [ -d "/workspace" ]; then
    echo "📋 [LOG] Searching for Python traceback files..."
    find /workspace /tmp -name "*.log" -o -name "*error*" -o -name "*traceback*" 2>/dev/null | head -5 | while read -r logfile; do
        echo "📋 [LOG] Found: $logfile"
        if [ -r "$logfile" ]; then
            echo "📋 [LOG]   Last few lines:"
            tail -3 "$logfile" 2>/dev/null | while read -r line; do
                echo "📋 [LOG]     $line"
            done
        fi
    done
fi

# --- Final Assessment ---
echo ""
echo "🎯 [ASSESSMENT] Diagnosis Summary:"

# Count issues found
issues=0

# Check critical paths
if [ ! -d "${STORAGE_ROOT:-/workspace}/models" ]; then
    echo "🎯 [ASSESSMENT] ❌ CRITICAL: Models directory missing"
    ((issues++))
fi

if [ ! -w "${STORAGE_ROOT:-/workspace}" ]; then
    echo "🎯 [ASSESSMENT] ❌ CRITICAL: Cannot write to storage root"
    ((issues++))
fi

# Check for stranded files
stranded_files=$(find /workspace/downloads_tmp -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" 2>/dev/null | wc -l)
if [ "$stranded_files" -gt 0 ]; then
    echo "🎯 [ASSESSMENT] ⚠️ WARNING: $stranded_files files stranded in downloads_tmp"
    ((issues++))
fi

# Check model availability
organized_files=$(find "${STORAGE_ROOT:-/workspace}/models" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" 2>/dev/null | wc -l)
if [ "$organized_files" -eq 0 ]; then
    echo "🎯 [ASSESSMENT] ❌ CRITICAL: No models available to ComfyUI"
    ((issues++))
fi

echo ""
if [ $issues -eq 0 ]; then
    echo "🎯 [ASSESSMENT] ✅ System appears healthy - no major issues detected"
elif [ $issues -le 2 ]; then
    echo "🎯 [ASSESSMENT] ⚠️ Minor issues detected - system may function with limitations"
else
    echo "🎯 [ASSESSMENT] ❌ Multiple critical issues detected - system likely non-functional"
fi

echo "🎯 [ASSESSMENT] Total issues found: $issues"
echo ""
echo "🔍 [DIAGNOSIS] Diagnosis complete. Use this information to:"
echo "🔍 [DIAGNOSIS] 1. Identify permission/ownership problems"
echo "🔍 [DIAGNOSIS] 2. Locate stranded model files"
echo "🔍 [DIAGNOSIS] 3. Verify service functionality"
echo "🔍 [DIAGNOSIS] 4. Plan recovery actions"