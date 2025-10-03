# ComfyUI Pod Template - Enhanced for RunPod Deployment
# Based on PyTorch 2.5.1 with CUDA 12.4+ support for modern GPUs
FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

# Use bash with pipefail for safer RUN steps
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    WORKSPACE=/workspace \
    COMFYUI_DIR=/opt/ComfyUI \
    MODELS_DIR=/workspace/models \
    HF_HOME=/workspace/.cache/huggingface \
    HF_HUB_ENABLE_HF_TRANSFER=1 \
    HF_HUB_DISABLE_TELEMETRY=1 \
    PIP_NO_CACHE_DIR=1 \
    TZ=UTC \
    LISTEN_HOST=0.0.0.0 \
    COMFYUI_PORT=8188 \
    API_PORT=8000 \
    CUDA_LAUNCH_BLOCKING=1 \
    TORCH_USE_CUDA_DSA=1 \
    CUDA_MODULE_LOADING=LAZY \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
    COMFYUI_EXTRA_ARGS= \
    INSTALL_FACEID_MODELS=true \
    FACEID_HF_REPOS="h94/IP-Adapter-FaceID,h94/IP-Adapter" \
    FACEID_HF_FILES=""

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget ca-certificates tini ffmpeg aria2 \
    libgl1 libglib2.0-0 build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install latest PyTorch with CUDA 12.4+ support
RUN pip install --upgrade pip && \
    pip install torch==2.5.1 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 && \
    pip install --upgrade nvidia-ml-py3

# Python dependencies
COPY requirements.txt /opt/requirements.txt
RUN pip install --no-cache-dir -r /opt/requirements.txt && \
    pip install --no-cache-dir -U insightface onnx onnxruntime onnxsim scikit-image piexif

# Install FileBrowser (optional)
RUN curl -L -o /tmp/fb.tar.gz https://github.com/filebrowser/filebrowser/releases/latest/download/linux-amd64-filebrowser.tar.gz && \
    tar -xzf /tmp/fb.tar.gz -C /usr/local/bin filebrowser && \
    chmod +x /usr/local/bin/filebrowser && \
    rm /tmp/fb.tar.gz

# Clone ComfyUI
ARG COMFYUI_REF=master
RUN git clone --depth=1 --branch ${COMFYUI_REF} https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_DIR} && \
    pip install --no-cache-dir -r ${COMFYUI_DIR}/requirements.txt

# Prepare workspace and symlinks
RUN mkdir -p ${WORKSPACE} ${MODELS_DIR} && \
    mkdir -p ${COMFYUI_DIR}/custom_nodes && \
    rm -rf ${COMFYUI_DIR}/models && \
    ln -s ${MODELS_DIR} ${COMFYUI_DIR}/models

# Pre-install essential custom nodes
RUN set -eux; \
    cd ${COMFYUI_DIR}/custom_nodes && \
    for repo in \
        https://github.com/ltdrdata/ComfyUI-Manager.git \
        https://github.com/ltdrdata/ComfyUI-Impact-Pack.git \
        https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git \
        https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git \
        https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git \
        https://github.com/kijai/ComfyUI-KJNodes.git \
        https://github.com/rgthree/rgthree-comfy.git \
        https://github.com/cubiq/ComfyUI_IPAdapter_plus.git \
        https://github.com/WASasquatch/was-node-suite-comfyui.git \
        https://github.com/ClownsharkBatwing/RES4LYF.git \
        https://github.com/yolain/ComfyUI-Easy-Use.git; \
    do \
        repo_dir=$(basename "$repo" .git); \
        if [ ! -d "$repo_dir" ]; then \
            git clone --depth=1 "$repo" || true; \
            if [ -f "$repo_dir/requirements.txt" ]; then \
                pip install --no-cache-dir -r "$repo_dir/requirements.txt" || true; \
            fi; \
            if [ -f "$repo_dir/install.py" ]; then \
                python "$repo_dir/install.py" || true; \
            fi; \
        fi; \
    done

# Create unprivileged user
RUN useradd -m -u 1000 -s /bin/bash comfy && \
    chown -R comfy:comfy ${WORKSPACE} ${COMFYUI_DIR} /usr/local && \
    mkdir -p ${WORKSPACE}/inputs ${WORKSPACE}/outputs && \
    chown -R comfy:comfy ${WORKSPACE}

# Add scripts
COPY --chown=comfy:comfy bin/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=comfy:comfy scripts/ /opt/scripts/
COPY --chown=comfy:comfy serverless/ /opt/serverless/
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    chmod +x /opt/scripts/*.sh && \
    chmod +x /opt/scripts/*.py && \
    chown -R comfy:comfy /opt/scripts /opt/serverless

EXPOSE 8188 8888 8090 8000

WORKDIR ${COMFYUI_DIR}

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
  CMD curl -fsS http://127.0.0.1:${COMFYUI_PORT}/ || exit 1

USER comfy

ENTRYPOINT ["/usr/bin/tini", "-s", "-g", "--", "/usr/local/bin/entrypoint.sh"]