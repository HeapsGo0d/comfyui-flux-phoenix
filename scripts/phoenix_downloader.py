#!/usr/bin/env python3
"""
Phoenix Download Manager - Python Implementation
Based on Hearmean's reliable approach but adapted for our use case
"""

import requests
import os
import subprocess
import sys
import json
from pathlib import Path
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


class PhoenixDownloader:
    def __init__(self, debug_mode=False):
        self.debug_mode = debug_mode
        self.download_tmp_dir = Path("/workspace/downloads_tmp")
        self.download_tmp_dir.mkdir(exist_ok=True)
        self.session = self._create_session()

    def _create_session(self):
        """Create a requests session with retry logic."""
        session = requests.Session()
        retry_strategy = Retry(
            total=5,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET", "OPTIONS"]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("https://", adapter)
        session.mount("http://", adapter)
        return session

    def log(self, message, is_debug=False):
        """Logging function with debug support"""
        prefix = "[DOWNLOAD-DEBUG]" if is_debug else "[DOWNLOAD]"
        if is_debug and not self.debug_mode:
            return
        print(f"  {prefix} {message}")
        
    def download_hf_repos(self, repos_list, token=None):
        """Download HuggingFace repositories"""
        if not repos_list:
            self.log("No Hugging Face repos specified to download.")
            return True
            
        self.log("Found Hugging Face repos to download...")
        
        repos = [repo.strip() for repo in repos_list.split(',') if repo.strip()]
        
        for repo_id in repos:
            self.log(f"Starting HF download: {repo_id}")
            
            # Build huggingface-cli command
            cmd = [
                'huggingface-cli', 'download',
                repo_id,
                '--local-dir', str(self.download_tmp_dir / repo_id),
                '--local-dir-use-symlinks', 'False',
                '--resume-download'
            ]
            
            if token:
                cmd.extend(['--token', token])
                self.log("Using provided HuggingFace token", is_debug=True)
            else:
                self.log("No HuggingFace token provided", is_debug=True)
            
            try:
                if self.debug_mode:
                    self.log(f"Running: {' '.join(cmd)}", is_debug=True)
                    result = subprocess.run(cmd, check=True)
                else:
                    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
                    
                self.log(f"✅ Completed HF download: {repo_id}")
                
                if self.debug_mode:
                    # Show download size
                    try:
                        size_result = subprocess.run(['du', '-sh', str(self.download_tmp_dir / repo_id)], 
                                                   capture_output=True, text=True)
                        if size_result.returncode == 0:
                            size = size_result.stdout.split()[0]
                            self.log(f"Downloaded size: {size}", is_debug=True)
                    except:
                        pass
                        
            except subprocess.CalledProcessError as e:
                self.log(f"❌ ERROR: Failed to download '{repo_id}'.")
                if not token:
                    self.log("   HINT: This is likely a private/gated repository. Please provide a")
                    self.log("   HUGGINGFACE_TOKEN via RunPod Secrets ('huggingface.co').")
                else:
                    self.log("   HINT: Please check if your token is valid and has access to this repository.")
                self.log("   ⏭️ Continuing with remaining downloads...")
                continue
                
        return True
        
    def get_civitai_model_info(self, model_id, token=None):
        """Get model info from CivitAI API using Hearmean's approach"""
        headers = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
            
        # Use model-versions endpoint like Hearmean
        api_url = f"https://civitai.com/api/v1/model-versions/{model_id}"
        
        self.log(f"Fetching metadata from: {api_url}", is_debug=True)
        
        try:
            response = self.session.get(api_url, headers=headers, timeout=30)
            response.raise_for_status()

            if response.status_code == 200:
                data = response.json()
                if 'files' in data and data['files']:
                    file_info = data['files'][0]  # Get first file
                    return {
                        'filename': file_info.get('name'),
                        'download_url': f"https://civitai.com/api/download/models/{model_id}?type=Model&format=SafeTensor",
                        'hash': file_info.get('hashes', {}).get('SHA256', '').lower()
                    }
            
            self.log(f"Invalid API response structure for model {model_id}", is_debug=True)
            return None
            
        except requests.RequestException as e:
            self.log(f"API request failed for model {model_id}: {e}", is_debug=True)
            return None
            
    def download_civitai_model(self, model_id, model_type, token=None):
        """Download single model from CivitAI using Hearmean's method"""
        if not model_id:
            return True
            
        self.log(f"Processing Civitai model ID: {model_id}", is_debug=True)
        
        # Get model info
        model_info = self.get_civitai_model_info(model_id, token)
        if not model_info or not model_info['filename']:
            self.log(f"❌ ERROR: Could not retrieve metadata for Civitai model ID {model_id}.")
            return False
            
        filename = model_info['filename']
        download_url = model_info['download_url']
        remote_hash = model_info['hash']
        
        self.log(f"Filename: {filename}", is_debug=True)
        self.log(f"Download URL: {download_url[:50]}...", is_debug=True)
        
        # Check if file already exists
        storage_root = os.environ.get('STORAGE_ROOT', '/workspace')
        models_dir = Path(storage_root) / 'models'
        
        if self._file_exists_in_models(models_dir, filename):
            self.log(f"ℹ️ Skipping download for '{filename}', file already exists.")
            return True
            
        self.log(f"Starting Civitai download: {filename} ({model_type})")
        
        # Build aria2c command like Hearmean, but add token to URL
        if token:
            download_url += f"&token={token}"
            
        cmd = [
            'aria2c',
            '-x', '8',
            '-s', '8',
            '--continue=true',
            '--console-log-level=warn' if not self.debug_mode else '--console-log-level=info',
            '--summary-interval=0' if not self.debug_mode else '--summary-interval=10',
            f'--dir={self.download_tmp_dir}',
            f'--out={filename}',
            download_url
        ]
        
        try:
            if self.debug_mode:
                self.log(f"Starting download with progress...", is_debug=True)
                
            result = subprocess.run(cmd, check=True)
            
            # Verify checksum if available
            if remote_hash:
                downloaded_file = self.download_tmp_dir / filename
                if self._verify_checksum(downloaded_file, remote_hash):
                    self.log(f"✅ Checksum PASSED for {filename}.")
                else:
                    self.log(f"❌ ERROR: Checksum FAILED for {filename}.")
                    downloaded_file.unlink(missing_ok=True)
                    return False
            else:
                self.log(f"No checksum available for {filename}, skipping validation", is_debug=True)
                
            self.log(f"✅ Completed Civitai download: {filename}")
            return True
            
        except subprocess.CalledProcessError as e:
            self.log(f"❌ ERROR: Failed to download {filename} from Civitai.")
            return False
            
    def _file_exists_in_models(self, models_dir, filename):
        """Check if file exists anywhere in models directory"""
        try:
            for path in models_dir.rglob(filename):
                if path.is_file():
                    return True
        except:
            pass
        return False
        
    def _verify_checksum(self, file_path, expected_hash):
        """Verify SHA256 checksum"""
        try:
            result = subprocess.run(['sha256sum', str(file_path)], 
                                  capture_output=True, text=True, check=True)
            actual_hash = result.stdout.split()[0].lower()
            return actual_hash == expected_hash.lower()
        except:
            return False
            
    def process_civitai_downloads(self, download_list, model_type, token=None):
        """Process comma-separated list of CivitAI downloads"""
        if not download_list:
            self.log(f"No Civitai {model_type}s specified to download.")
            return True
            
        self.log(f"Found Civitai {model_type}s to download...")
        self.log(f"Processing list: {download_list}", is_debug=True)
        
        ids = [id.strip() for id in download_list.split(',') if id.strip()]
        successful = 0
        failed = 0
        
        for model_id in ids:
            if self.download_civitai_model(model_id, model_type, token):
                successful += 1
            else:
                failed += 1
                self.log(f"⏭️ Continuing with remaining {model_type}s...")
                
        self.log(f"Civitai {model_type}s complete: {successful} successful, {failed} failed")
        return True


def main():
    """Main download orchestration"""
    # Get environment variables
    debug_mode = os.getenv('DEBUG_MODE', 'false').lower() == 'true'
    hf_repos = os.getenv('HF_REPOS_TO_DOWNLOAD', '')
    hf_token = os.getenv('HUGGINGFACE_TOKEN', '')
    civitai_token = os.getenv('CIVITAI_TOKEN', '')
    civitai_checkpoints = os.getenv('CIVITAI_CHECKPOINTS_TO_DOWNLOAD', '')
    civitai_loras = os.getenv('CIVITAI_LORAS_TO_DOWNLOAD', '')
    civitai_vaes = os.getenv('CIVITAI_VAES_TO_DOWNLOAD', '')
    
    # Initialize downloader
    downloader = PhoenixDownloader(debug_mode=debug_mode)
    
    downloader.log("Initializing Python download manager...")
    
    if debug_mode:
        downloader.log("Debug mode enabled - showing detailed progress", is_debug=True)
        downloader.log(f"HF_REPOS_TO_DOWNLOAD: {hf_repos or '<empty>'}", is_debug=True)
        downloader.log(f"CIVITAI_CHECKPOINTS_TO_DOWNLOAD: {civitai_checkpoints or '<empty>'}", is_debug=True)
        downloader.log(f"CIVITAI_LORAS_TO_DOWNLOAD: {civitai_loras or '<empty>'}", is_debug=True)
        downloader.log(f"CIVITAI_VAES_TO_DOWNLOAD: {civitai_vaes or '<empty>'}", is_debug=True)
    
    # Process downloads
    downloader.download_hf_repos(hf_repos, hf_token)
    downloader.process_civitai_downloads(civitai_checkpoints, "Checkpoint", civitai_token)
    downloader.process_civitai_downloads(civitai_loras, "LoRA", civitai_token)
    downloader.process_civitai_downloads(civitai_vaes, "VAE", civitai_token)
    
    downloader.log("All downloads complete.")
    
    # Debug summary
    if debug_mode:
        downloader.log("=== DOWNLOAD SUMMARY ===", is_debug=True)
        if downloader.download_tmp_dir.exists():
            try:
                files = list(downloader.download_tmp_dir.rglob('*'))
                files = [f for f in files if f.is_file()]
                if files:
                    downloader.log("Downloaded files:", is_debug=True)
                    for file in files[:10]:  # Show first 10 files
                        size_result = subprocess.run(['ls', '-lh', str(file)], 
                                                   capture_output=True, text=True)
                        if size_result.returncode == 0:
                            downloader.log(f"  {size_result.stdout.strip()}", is_debug=True)
                    
                    # Total size
                    size_result = subprocess.run(['du', '-sh', str(downloader.download_tmp_dir)], 
                                               capture_output=True, text=True)
                    if size_result.returncode == 0:
                        total_size = size_result.stdout.split()[0]
                        downloader.log(f"Total download size: {total_size}", is_debug=True)
                else:
                    downloader.log("No files downloaded", is_debug=True)
            except Exception as e:
                downloader.log(f"Error generating summary: {e}", is_debug=True)
        downloader.log("=== END SUMMARY ===", is_debug=True)


if __name__ == "__main__":
    main()