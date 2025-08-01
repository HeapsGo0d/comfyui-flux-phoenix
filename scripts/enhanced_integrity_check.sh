#!/bin/bash
set -euo pipefail
# ==================================================================================
# PHOENIX: ENHANCED INTEGRITY VERIFICATION
# ==================================================================================
# Comprehensive verification of file organization and system state

# --- Enhanced Integrity Check Function ---
verify_model_organization() {
    echo "🔍 [INTEGRITY] Starting comprehensive post-organization integrity check..."
    
    local storage_root="${STORAGE_ROOT:-/workspace}"
    local models_dir="${storage_root}/models"
    local downloads_tmp="/workspace/downloads_tmp"
    
    # Initialize counters
    local downloads_count=0
    local models_count=0
    local total_size_downloads="0"
    local total_size_models="0"
    local error_count=0
    
    echo "🔍 [INTEGRITY] Scanning file system..."
    echo "🔍 [INTEGRITY] Storage root: ${storage_root}"
    echo "🔍 [INTEGRITY] Models directory: ${models_dir}"
    
    # Check downloads_tmp directory
    if [ -d "$downloads_tmp" ]; then
        downloads_count=$(find "$downloads_tmp" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" 2>/dev/null | wc -l)
        total_size_downloads=$(du -sb "$downloads_tmp" 2>/dev/null | cut -f1 || echo "0")
        echo "🔍 [INTEGRITY] Downloads directory exists with ${downloads_count} model files"
    else
        echo "🔍 [INTEGRITY] Downloads directory does not exist (cleaned up)"
    fi
    
    # Check models directory structure
    if [ -d "$models_dir" ]; then
        models_count=$(find "$models_dir" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" 2>/dev/null | wc -l)
        total_size_models=$(du -sb "$models_dir" 2>/dev/null | cut -f1 || echo "0")
        
        echo "🔍 [INTEGRITY] Models directory structure:"
        local categories=("checkpoints" "loras" "vae" "controlnet" "upscale_models" "embeddings" "clip" "unet" "diffusion_models")
        
        for category in "${categories[@]}"; do
            local category_dir="${models_dir}/${category}"
            if [ -d "$category_dir" ]; then
                local category_count=$(find "$category_dir" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" 2>/dev/null | wc -l)
                local category_size=$(du -sb "$category_dir" 2>/dev/null | cut -f1 || echo "0")
                
                if [ "$category_count" -gt 0 ]; then
                    echo "🔍 [INTEGRITY]   📁 ${category}/: ${category_count} files ($(numfmt --to=iec $category_size))"
                    
                    # Show sample files in debug mode
                    if [ "${DEBUG_MODE:-false}" = "true" ]; then
                        find "$category_dir" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" 2>/dev/null | head -3 | while read -r file; do
                            local file_size=$(stat -c%s "$file" 2>/dev/null || echo "0")
                            echo "🔍 [INTEGRITY]     • $(basename "$file") ($(numfmt --to=iec $file_size))"
                        done
                    fi
                else
                    echo "🔍 [INTEGRITY]   📁 ${category}/: empty"
                fi
            else
                echo "🔍 [INTEGRITY]   📁 ${category}/: directory missing"
                ((error_count++))
            fi
        done
    else
        echo "🔍 [INTEGRITY] ❌ Models directory does not exist: ${models_dir}"
        ((error_count++))
    fi
    
    # Summary statistics
    echo "🔍 [INTEGRITY] === SUMMARY ==="
    echo "🔍 [INTEGRITY] Files in downloads_tmp: ${downloads_count}"
    echo "🔍 [INTEGRITY] Files in models/: ${models_count}"
    echo "🔍 [INTEGRITY] Size in downloads_tmp: $(numfmt --to=iec ${total_size_downloads})"
    echo "🔍 [INTEGRITY] Size in models/: $(numfmt --to=iec ${total_size_models})"
    
    # File accessibility tests
    echo "🔍 [INTEGRITY] Testing file accessibility..."
    local accessible_files=0
    local inaccessible_files=0
    
    if [ -d "$models_dir" ]; then
        while IFS= read -r -d '' file; do
            if [ -r "$file" ] && [ -s "$file" ]; then
                ((accessible_files++))
            else
                ((inaccessible_files++))
                echo "🔍 [INTEGRITY] ❌ Inaccessible file: $(basename "$file")"
                ls -la "$file" 2>/dev/null || echo "🔍 [INTEGRITY]   File info unavailable"
            fi
        done < <(find "$models_dir" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" -print0 2>/dev/null)
    fi
    
    echo "🔍 [INTEGRITY] Accessible files: ${accessible_files}"
    echo "🔍 [INTEGRITY] Inaccessible files: ${inaccessible_files}"
    
    # FileBrowser compatibility check
    echo "🔍 [INTEGRITY] Testing FileBrowser compatibility..."
    if [ -d "$storage_root" ] && [ -r "$storage_root" ]; then
        echo "🔍 [INTEGRITY] ✅ Storage root is accessible to FileBrowser"
        
        # Test if FileBrowser can see the models directory
        if [ -d "$models_dir" ] && [ -r "$models_dir" ]; then
            echo "🔍 [INTEGRITY] ✅ Models directory is accessible to FileBrowser"
        else
            echo "🔍 [INTEGRITY] ❌ Models directory is NOT accessible to FileBrowser"
            ((error_count++))
        fi
    else
        echo "🔍 [INTEGRITY] ❌ Storage root is NOT accessible to FileBrowser"
        ((error_count++))
    fi
    
    # ComfyUI symlink verification
    echo "🔍 [INTEGRITY] Verifying ComfyUI symlinks..."
    local comfyui_dir="/workspace/ComfyUI"
    
    if [ -d "$comfyui_dir" ]; then
        local links_to_check=("models" "input" "output")
        for link_name in "${links_to_check[@]}"; do
            local link_path="${comfyui_dir}/${link_name}"
            if [ -L "$link_path" ]; then
                local target=$(readlink "$link_path")
                if [ -d "$target" ]; then
                    echo "🔍 [INTEGRITY] ✅ ComfyUI ${link_name} symlink: ${link_path} → ${target}"
                else
                    echo "🔍 [INTEGRITY] ❌ ComfyUI ${link_name} symlink broken: ${link_path} → ${target}"
                    ((error_count++))
                fi
            else
                echo "🔍 [INTEGRITY] ⚠️ ComfyUI ${link_name} symlink missing: ${link_path}"
            fi
        done
    else
        echo "🔍 [INTEGRITY] ⚠️ ComfyUI directory not found: ${comfyui_dir}"
    fi
    
    # Permissions analysis
    if [ "${DEBUG_MODE:-false}" = "true" ] && [ -d "$models_dir" ]; then
        echo "🔍 [INTEGRITY] Permissions analysis (debug mode):"
        echo "🔍 [INTEGRITY] Models directory permissions:"
        ls -la "$models_dir" | head -5 | while read -r line; do
            echo "🔍 [INTEGRITY]   $line"
        done
        
        # Check ownership
        local models_owner=$(stat -c '%U:%G' "$models_dir" 2>/dev/null || echo "unknown")
        local current_user=$(whoami)
        echo "🔍 [INTEGRITY] Models directory owner: ${models_owner}"
        echo "🔍 [INTEGRITY] Current user: ${current_user}"
        
        # Check if current user can write to models directory
        if [ -w "$models_dir" ]; then
            echo "🔍 [INTEGRITY] ✅ Current user can write to models directory"
        else
            echo "🔍 [INTEGRITY] ❌ Current user CANNOT write to models directory"
            ((error_count++))
        fi
    fi
    
    # Final assessment
    echo "🔍 [INTEGRITY] === FINAL ASSESSMENT ==="
    
    if [ "$models_count" -gt 0 ] && [ "$inaccessible_files" -eq 0 ] && [ "$error_count" -eq 0 ]; then
        echo "🔍 [INTEGRITY] ✅ EXCELLENT: All systems functioning perfectly"
        echo "🔍 [INTEGRITY]   • ${models_count} model files successfully organized"
        echo "🔍 [INTEGRITY]   • All files accessible"
        echo "🔍 [INTEGRITY]   • FileBrowser compatibility confirmed"
        echo "🔍 [INTEGRITY]   • ComfyUI integration ready"
        return 0
    elif [ "$models_count" -gt 0 ] && [ "$error_count" -le 2 ]; then
        echo "🔍 [INTEGRITY] ✅ GOOD: Models organized with minor issues"
        echo "🔍 [INTEGRITY]   • ${models_count} model files available"
        echo "🔍 [INTEGRITY]   • ${error_count} minor issues detected"
        echo "🔍 [INTEGRITY]   • System should function normally"
        return 0
    elif [ "$models_count" -gt 0 ]; then
        echo "🔍 [INTEGRITY] ⚠️ PARTIAL: Models present but significant issues detected"
        echo "🔍 [INTEGRITY]   • ${models_count} model files found"
        echo "🔍 [INTEGRITY]   • ${error_count} issues require attention"
        echo "🔍 [INTEGRITY]   • Some functionality may be limited"
        return 1
    elif [ "$downloads_count" -gt 0 ]; then
        echo "🔍 [INTEGRITY] ❌ FAILURE: Files downloaded but organization failed"
        echo "🔍 [INTEGRITY]   • ${downloads_count} files remain in downloads_tmp"
        echo "🔍 [INTEGRITY]   • Organization process needs investigation"
        echo "🔍 [INTEGRITY]   • Manual file movement may be required"
        return 1
    else
        echo "🔍 [INTEGRITY] ❌ CRITICAL: No model files found in system"
        echo "🔍 [INTEGRITY]   • Downloads may have failed"
        echo "🔍 [INTEGRITY]   • Organization process failed"
        echo "🔍 [INTEGRITY]   • System unusable for model inference"
        return 1
    fi
}

# --- Recovery Suggestions ---
suggest_recovery_actions() {
    echo "🔧 [RECOVERY] Suggested recovery actions:"
    
    local downloads_tmp="/workspace/downloads_tmp"
    local models_dir="${STORAGE_ROOT:-/workspace}/models"
    
    if [ -d "$downloads_tmp" ]; then
        local downloads_count=$(find "$downloads_tmp" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" -o -name "*.bin" 2>/dev/null | wc -l)
        
        if [ "$downloads_count" -gt 0 ]; then
            echo "🔧 [RECOVERY] 1. Files exist in downloads_tmp - retry organization:"
            echo "🔧 [RECOVERY]    source /usr/local/bin/scripts/organizer.sh"
            echo "🔧 [RECOVERY] 2. Manual file movement:"
            echo "🔧 [RECOVERY]    cp -r ${downloads_tmp}/* ${models_dir}/checkpoints/"
            echo "🔧 [RECOVERY] 3. Check permissions:"
            echo "🔧 [RECOVERY]    ls -la ${models_dir}"
        fi
    fi
    
    if [ ! -d "$models_dir" ]; then
        echo "🔧 [RECOVERY] Models directory missing - recreate structure:"
        echo "🔧 [RECOVERY]    mkdir -p ${models_dir}/{checkpoints,loras,vae,controlnet,upscale_models,embeddings,clip,unet,diffusion_models}"
        echo "🔧 [RECOVERY]    chmod 755 ${models_dir}/*"
    fi
    
    echo "🔧 [RECOVERY] 4. Restart services after manual fixes:"
    echo "🔧 [RECOVERY]    pkill -f filebrowser && source /usr/local/bin/scripts/service_manager.sh"
    echo "🔧 [RECOVERY] 5. Check service logs:"
    echo "🔧 [RECOVERY]    curl -s http://localhost:8188/system_stats || echo 'ComfyUI not responding'"
    echo "🔧 [RECOVERY]    curl -s http://localhost:8080 || echo 'FileBrowser not responding'"
}

# Execute the integrity check
verify_model_organization
exit_code=$?

# Show recovery suggestions if there are issues
if [ $exit_code -ne 0 ]; then
    suggest_recovery_actions
fi

exit $exit_code