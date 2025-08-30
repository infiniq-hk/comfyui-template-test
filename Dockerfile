# ComfyUI on RunPod with Civitai/HuggingFace support
# Base image: PyTorch + CUDA 12.1 + cuDNN 9
FROM pytorch/pytorch:2.4.0-cuda12.1-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    WORKSPACE=/workspace \
    COMFYUI_DIR=/opt/ComfyUI \
    MODELS_DIR=/workspace/models \
    HF_HOME=/workspace/.cache/huggingface \
    PIP_NO_CACHE_DIR=1

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget ca-certificates tini ffmpeg aria2 \
    libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

# Python deps used across scripts
RUN pip install --upgrade pip && \
    pip install --no-cache-dir \
    requests tqdm pydantic typing-extensions \
    huggingface-hub==0.24.6 \
    hf-transfer \
    civitai==0.1.5 \
    jupyterlab || true

# Install FileBrowser
RUN curl -L -o /tmp/fb.tar.gz https://github.com/filebrowser/filebrowser/releases/latest/download/linux-amd64-filebrowser.tar.gz && \
    tar -xzf /tmp/fb.tar.gz -C /usr/local/bin filebrowser && \
    chmod +x /usr/local/bin/filebrowser && \
    rm /tmp/fb.tar.gz

# Clone ComfyUI
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_DIR} && \
    pip install --no-cache-dir -r ${COMFYUI_DIR}/requirements.txt

# Prepare workspace and symlinks to persist models on RunPod's /workspace volume
RUN mkdir -p ${WORKSPACE} ${MODELS_DIR} && \
    mkdir -p ${COMFYUI_DIR}/custom_nodes && \
    rm -rf ${COMFYUI_DIR}/models && \
    ln -s ${MODELS_DIR} ${COMFYUI_DIR}/models

# Add scripts
COPY bin/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/ /opt/scripts/
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    chmod +x /opt/scripts/*.sh || true

EXPOSE 8188

WORKDIR ${COMFYUI_DIR}

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]


