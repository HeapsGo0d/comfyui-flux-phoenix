Here's a refined, comprehensive initial requirements list for the **ComfyUI FLUX RTX5090 RunPod Template (Codename: Phoenix)**, integrating your latest clarifications and the additional points provided:

---

# 🚀 **Project Scope & Requirements**

### **Project Name:**

**ComfyUI FLUX RTX5090 RunPod Template (Codename: Phoenix)**

### **Version:**

**1.0 (Brainstorm)**

### **Project Description:**

A clean-slate, secure, high-performance Docker-based RunPod template optimized specifically for ComfyUI with FLUX models, designed explicitly for NVIDIA RTX 5090 GPUs.

---

## 🎯 **Core Project Goals**

1. **Peak Performance**

   * Optimized inference speeds utilizing NVIDIA official PyTorch container (`nvcr.io/nvidia/pytorch:latest-py3`).
   * CUDA and PyTorch compiled specifically for RTX 5090 (CUDA Arch sm\_90a, sm\_120).
   * Efficient downloads (using `aria2c`) and parallel model handling.

2. **Maximum Security & Privacy**

   * **"Leave-No-Trace" Forensic Cleanup**: Ensure no residual data, logs, credentials, or temporary files remain upon container exit.
   * System-level hardening: Restrictive permissions, disabled history, no Python bytecode, token scrubbing, secure deletion (`shred`).

3. **Ease of Use & Maintainability**

   * Clearly modularized, well-documented scripts with clean directory structures.
   * Easy configuration through intuitive and descriptive template environment variables.

4. **Reliability & Robustness**

   * Comprehensive error handling, graceful exits, intelligent fallbacks.
   * Health checks for ComfyUI availability, self-healing mechanisms where feasible.

---

## 🔧 **Technical Architecture**

### **Base Docker Image**

* NVIDIA official PyTorch Container:

  * Source: `nvcr.io/nvidia/pytorch:latest-py3`
  * Justification: Pre-compiled, optimized, maintained for RTX 5090.

### **Scripting Modularity**

* Clear modular structure:

  * `entrypoint.sh`: Main orchestrator, signal trapping.
  * `scripts/system_setup.sh`: GPU checks, environment validation.
  * `scripts/download_manager.sh`: Manages all model downloads from CivitAI/HuggingFace.
  * `scripts/organizer.sh`: Moves downloaded files intelligently to ComfyUI folders.
  * `scripts/service_manager.sh`: Starts/stops ComfyUI & FileBrowser.
  * `scripts/forensic_cleanup.sh`: Securely removes sensitive data on exit.

### **Storage Strategy**

* **Default:** Ephemeral storage (`/workspace`, 100GB temp space).
* **Optional Persistent Storage:** Fully supported via template variable (`USE_VOLUME`). Auto-detection with intelligent path switching.

---

## 📦 **Docker Build Strategy**

* **Multi-stage Build:**

  * Builder stage: Compile/download required binaries.
  * Final stage: Minimal runtime image for rapid start-up.

* **Optimized Dependencies:**

  * Python (`pip`): `comfyui`, `huggingface_hub[cli]`, `accelerate`, `transformers`, `opencv-python-headless`, `aria2p`, `xformers (--no-deps)`
  * System: `aria2`, `git`, `unzip`, `htop`, `nano`, `vim`, `libjpeg-dev`, `libpng-dev`, `shred`
  * **Explicit Pillow Install** for image compatibility.

* **Component Pre-installation:**

  * ComfyUI (clean state, official repository clone)
  * FileBrowser (binary pre-downloaded to `/usr/local/bin`)

---

## 🛡️ **Security & Privacy**

* Dedicated non-root user (`sduser`) with restricted permissions (`umask 077`).
* Disabled bash/python history, no Python bytecode generation (`PYTHONDONTWRITEBYTECODE=1`).
* Token security: Tokens unset immediately after use.
* Environment variables scrubbed, secure deletion of sensitive files.
* Optional extreme forensic cleanup controlled by variable (`PARANOID_MODE=true`).

---

## 🌐 **Networking & Ports**

* **7860:** ComfyUI Web Interface (Standard Port)
* **8080:** FileBrowser Interface

---

## 🖥️ **RunPod Template Variables**

| Variable                          | Default                        | Description                                      |
| --------------------------------- | ------------------------------ | ------------------------------------------------ |
| `DEBUG_MODE`                      | `false`                        | Enables verbose logging and debugging details.   |
| `HUGGINGFACE_TOKEN`               | -                              | Token for downloading HuggingFace models/repos.  |
| `CIVITAI_TOKEN`                   | -                              | Token for downloading from CivitAI.              |
| `HF_REPOS_TO_DOWNLOAD`            | `black-forest-labs/FLUX.1-dev` | HuggingFace repos to download.                   |
| `CIVITAI_CHECKPOINTS_TO_DOWNLOAD` | -                              | Comma-separated model IDs from CivitAI.          |
| `CIVITAI_LORAS_TO_DOWNLOAD`       | -                              | Comma-separated LoRA IDs from CivitAI.           |
| `CIVITAI_VAES_TO_DOWNLOAD`        | -                              | Comma-separated VAE IDs from CivitAI.            |
| `EXTRA_PYTHON_PACKAGES`           | -                              | Additional Python packages to install.           |
| `FB_USERNAME`                     | `admin`                        | FileBrowser Username.                            |
| `FB_PASSWORD`                     | (auto-gen)                     | Password, auto-generated if not provided.        |
| `USE_VOLUME`                      | `false`                        | Switch to persistent storage if true.            |
| `PARANOID_MODE`                   | `false`                        | Enable extreme forensic cleanup on exit if true. |
| `COMFY_CUSTOM_NODE_GIT_URLS`      | -                              | URLs to auto-install custom ComfyUI nodes.       |

---

## 📂 **Intelligent Download Handling**

* Default HuggingFace repo (`black-forest-labs/FLUX.1-dev`).
* Robust handling for CivitAI checkpoints, LoRAs, embeddings, VAEs.
* JSON manifest (optional future consideration) for complex/nested download tasks.

---

## 🛠️ **Process & Service Management**

* Graceful exit: `trap` SIGINT, SIGTERM, EXIT.
* GPU detection and performance flags (`--bf16-unet`, `--cuda-malloc`).
* Comprehensive health check for ComfyUI endpoint availability.

---

## 📋 **Logging & Debugging**

* Clear, structured logs with timestamps, color-coded status (✅, ℹ️, ❌).
* Debug verbosity controlled by `DEBUG_MODE` variable.

---

## ✅ **Extras & Quality-of-Life Improvements**

* No JupyterLab installation.
* Simple status endpoint (optional refinement) for monitoring critical states (disk, VRAM).
* Support for Flux-specific embeddings and LoRAs.

---

## 🔍 **Additional Refinements Based on Your Questions**

* **Complex downloads (JSON manifest)?**
  Future enhancement if more granular control is needed.

* **Pre-compile models (ONNX/TensorRT)?**
  Not for initial version; possible future performance optimization.

* **Simple status endpoint?**
  Minimalist endpoint included to report container status, failures, and cleanup.

* **Paranoid forensic cleanup optional?**
  Controlled via `PARANOID_MODE=true` environment variable.

* **ComfyUI Custom Nodes?**
  Included via `COMFY_CUSTOM_NODE_GIT_URLS`.

---

## 📈 **Future Metrics (Optional)**

* Consider adding simple GPU metrics (memory usage, utilization) for potential future optimization.

---

## 📝 **README & Documentation**

* Clear README (`README.md`) with:

  * Template overview
  * Detailed environment variable descriptions
  * Usage instructions
  * Port explanations and service links
  * Security highlights

---

# 🔖 **Final Summary & Confirmation:**

* Fresh, clean, secure, modular design with no legacy code.
* High security standards ("leave-no-trace").
* Robust GPU (RTX 5090) optimized performance.
* Intelligent, modular scripts for ease of maintenance and use.
* Clear RunPod template configuration for flexibility and easy user adoption.

This refined and comprehensive set of requirements ensures the initial build matches your exact vision, maintains clarity, and remains scalable for future enhancements.
