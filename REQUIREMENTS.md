Here's your refined and structured `REQUIREMENTS.md` for easy readability, clarity, and maintainability:

---

# 📌 REQUIREMENTS.md (Version 1.1)

**Project Name:**
**ComfyUI FLUX RTX5090 RunPod Template (Codename: Phoenix)**

**Version:**
**1.1 (Post-Review Refinement)**

**Description:**
A clean-slate, secure, stable, and high-performance Docker-based RunPod template optimized for ComfyUI with FLUX models, specifically designed for NVIDIA RTX 5090 GPUs. This release incorporates expert feedback to enhance stability, security, and maintainability.

---

## 🎯 **Core Project Goals**

| Goal                                  | Description                                                                                                       |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **🚀 Peak Performance**               | Optimized inference speeds utilizing NVIDIA's official PyTorch container and modern attention mechanisms.         |
| **🔒 Maximum Security & Privacy**     | Implements "leave-no-trace" forensic cleanup, rigorous system hardening, and **🆕 model integrity verification**. |
| **🛠️ Ease of Use & Maintainability** | Clearly modularized, documented scripts with **🆕 version-pinned dependencies** for greater stability.            |
| **✅ Reliability & Robustness**        | Comprehensive error handling, graceful shutdown procedures, intelligent fallbacks, and health monitoring.         |

---

## 🔧 **Technical Architecture**

### **Base Docker Image**

* **Source:** `nvcr.io/nvidia/pytorch:latest-py3`
* **Justification:** Delivers optimal balance of performance, reliability, and maintainability. Avoids fragile custom compilations while providing out-of-the-box support for RTX 5090.

### **Scripting & Configuration Modularity**

**Modular Script Structure:**

* ✅ `entrypoint.sh`: Main orchestrator, handles signal trapping.
* ✅ `scripts/system_setup.sh`: GPU checks and environment validation.
* ✅ `scripts/download_manager.sh`: Manages all model downloads.
* ✅ `scripts/organizer.sh`: Moves downloaded files intelligently.
* ✅ `scripts/service_manager.sh`: Starts and stops core services.
* ✅ `scripts/forensic_cleanup.sh`: Securely removes sensitive data on exit.

**🆕 Configuration File:**

* `config/versions.conf`: Pins exact versions (Git tags/hashes) of ComfyUI and critical dependencies to prevent unexpected issues.

### **Storage Strategy**

* **Default:** Ephemeral storage (`/workspace`).
* **🆕 Increased Temp Space:** Defaults to **150GB** temporary storage to better accommodate large FLUX models and user downloads.
* **Persistent Storage (Optional):** Fully supported via `USE_VOLUME=true`. Auto-detection with intelligent path switching.

---

## 🛡️ **Security & Privacy**

* ✅ Dedicated non-root user (`sduser`) with strict permissions (`umask 077`).
* ✅ Disabled command history and Python bytecode generation.
* ✅ Secure token handling (immediate unset after use).
* ✅ Optional extreme forensic cleanup (`PARANOID_MODE=true`).

**🆕 Enhanced Security Features:**

* **Model Integrity Verification:**

  * `download_manager.sh` verifies official SHA256 checksums from the Civitai API.
  * Downloads fail explicitly on checksum mismatches.
* **System Hardening:**

  * Disable core dumps (`ulimit -c 0`) to prevent memory writes to disk upon crashes.

---

## 🖥️ **RunPod Template Variables**

> **Note:** No changes to the variables themselves; tiered documentation is provided separately in the README.

| Variable                          | Default                        | Description                                     |
| --------------------------------- | ------------------------------ | ----------------------------------------------- |
| `DEBUG_MODE`                      | `false`                        | Enables verbose logging and debugging details.  |
| `HUGGINGFACE_TOKEN`               | -                              | Token for downloading HuggingFace models/repos. |
| `CIVITAI_TOKEN`                   | -                              | Token for downloading from Civitai.             |
| `HF_REPOS_TO_DOWNLOAD`            | `black-forest-labs/FLUX.1-dev` | HuggingFace repos to download.                  |
| `CIVITAI_CHECKPOINTS_TO_DOWNLOAD` | -                              | Comma-separated model IDs from Civitai.         |
| `CIVITAI_LORAS_TO_DOWNLOAD`       | -                              | Comma-separated LoRA IDs from Civitai.          |
| `CIVITAI_VAES_TO_DOWNLOAD`        | -                              | Comma-separated VAE IDs from Civitai.           |
| `EXTRA_PYTHON_PACKAGES`           | -                              | Additional Python packages to install.          |
| `FB_USERNAME`                     | `admin`                        | FileBrowser Username.                           |
| `FB_PASSWORD`                     | (auto-generated if empty)      | FileBrowser Password.                           |
| `USE_VOLUME`                      | `false`                        | Switches to persistent storage if true.         |
| `PARANOID_MODE`                   | `false`                        | Enables extreme forensic cleanup on exit.       |
| `COMFY_CUSTOM_NODE_GIT_URLS`      | -                              | URLs to auto-install custom ComfyUI nodes.      |

---

## ⚙️ **Process & Service Management**

* ✅ Graceful exit handling (`trap SIGINT SIGTERM EXIT`).
* ✅ Automatic GPU detection for optimized performance flags.

**🆕 Performance Optimizations:**

* ComfyUI startup flags to include:

  * Memory-saving options (`--bf16-unet`)
  * Modern attention mechanisms like **FlashAttention-2** by default.

---

## 📝 **README & Documentation**

* ✅ Clear and detailed `README.md` provided.

**🆕 Documentation Enhancements:**

* **VRAM/Storage Warning:** Prominent notice about high VRAM usage of FLUX and the recommended 150GB temporary storage allocation.
* **Tiered Documentation:** Environment variables structured into:

  * 📗 **Basic / Quick Start**
  * 📘 **Advanced Usage**

---

## 📈 **Future Roadmap (V2.0 and Beyond)**

| Area                           | Feature / Enhancement                                                                                                                                          |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Model Lifecycle Management** | Sophisticated automatic model quantization (FP16/8-bit) based on VRAM pressure, model swapping, storage deduplication, compression, and performance profiling. |
| **Performance Image**          | Experimental Docker image with PyTorch compiled from source for aggressive RTX 5090-specific optimizations.                                                    |
| **Enhanced Security**          | Integration of CI/CD pipeline vulnerability scanning for container images.                                                                                     |
| **Health API**                 | Simple status API endpoint reporting system status, health, and exact versions of key components.                                                              |

---

🔖 **Summary of Version 1.1 Improvements:**

* 📌 **150GB Default Storage** for improved handling of large FLUX models.
* 📌 **Pinned Dependencies** via `versions.conf` for stability.
* 📌 **SHA256 Model Integrity Verification** for secure downloads.
* 📌 **Core Dump Disabled** (`ulimit -c 0`) for enhanced system security.
* 📌 **FlashAttention-2 Enabled** by default for performance.
* 📌 **Enhanced Documentation** with clear VRAM/storage warnings.

---

**This document outlines all requirements clearly, providing a solid foundation for development, validation, and future enhancements.**
