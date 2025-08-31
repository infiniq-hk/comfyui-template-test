# ComfyUI on RunPod with Civitai/HuggingFace support
# Base image: PyTorch + CUDA 12.1 + cuDNN 9
FROM pytorch/pytorch:2.4.0-cuda12.1-cudnn9-runtime

# Use bash with pipefail for safer RUN steps
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    WORKSPACE=/workspace \
    COMFYUI_DIR=/opt/ComfyUI \
    MODELS_DIR=/workspace/models \
    HF_HOME=/workspace/.cache/huggingface \
    PIP_NO_CACHE_DIR=1 \
    TZ=UTC \
    LISTEN_HOST=0.0.0.0 \
    COMFYUI_PORT=8188 \
    COMFYUI_EXTRA_ARGS=

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
    jupyterlab opencv-python-headless || true

# Install FileBrowser
RUN curl -L -o /tmp/fb.tar.gz https://github.com/filebrowser/filebrowser/releases/latest/download/linux-amd64-filebrowser.tar.gz && \
    tar -xzf /tmp/fb.tar.gz -C /usr/local/bin filebrowser && \
    chmod +x /usr/local/bin/filebrowser && \
    rm /tmp/fb.tar.gz

# Clone ComfyUI
ARG COMFYUI_REF=master
RUN git clone --depth=1 --branch ${COMFYUI_REF} https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_DIR} && \
    pip install --no-cache-dir -r ${COMFYUI_DIR}/requirements.txt

# Prepare workspace and symlinks to persist models on RunPod's /workspace volume
RUN mkdir -p ${WORKSPACE} ${MODELS_DIR} && \
    mkdir -p ${COMFYUI_DIR}/custom_nodes && \
    rm -rf ${COMFYUI_DIR}/models && \
    ln -s ${MODELS_DIR} ${COMFYUI_DIR}/models

# Pre-install a comprehensive set of popular custom nodes
RUN set -eux; \
    cd ${COMFYUI_DIR}/custom_nodes && \
    for repo in \
        https://github.com/ltdrdata/ComfyUI-Manager.git \
        https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git \
        https://github.com/kijai/ComfyUI-KJNodes.git \
        https://github.com/rgthree/rgthree-comfy.git \
        https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git \
        https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git \
        https://github.com/Jordach/comfy-plasma.git \
        https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
        https://github.com/bash-j/mikey_nodes.git \
        https://github.com/ltdrdata/ComfyUI-Impact-Pack.git \
        https://github.com/Fannovel16/comfyui_controlnet_aux.git \
        https://github.com/yolain/ComfyUI-Easy-Use.git \
        https://github.com/kijai/ComfyUI-Florence2.git \
        https://github.com/ShmuelRonen/ComfyUI-LatentSyncWrapper.git \
        https://github.com/WASasquatch/was-node-suite-comfyui.git \
        https://github.com/theUpsider/ComfyUI-Logic.git \
        https://github.com/cubiq/ComfyUI_essentials.git \
        https://github.com/chrisgoringe/cg-image-picker.git \
        https://github.com/chflame163/ComfyUI_LayerStyle.git \
        https://github.com/chrisgoringe/cg-use-everywhere.git \
        https://github.com/ClownsharkBatwing/RES4LYF.git \
        https://github.com/welltop-cn/ComfyUI-TeaCache.git \
        https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git \
        https://github.com/Jonseed/ComfyUI-Detail-Daemon.git \
        https://github.com/kijai/ComfyUI-WanVideoWrapper.git \
        https://github.com/chflame163/ComfyUI_LayerStyle_Advance.git \
        https://github.com/BadCafeCode/masquerade-nodes-comfyui.git \
        https://github.com/1038lab/ComfyUI-RMBG.git \
        https://github.com/M1kep/ComfyLiterals.git \
        https://github.com/BlenderNeko/ComfyUI_Noise.git; \
    do \
        repo_dir=$(basename "$repo" .git); \
        if [ ! -d "$repo_dir" ]; then \
            if [ "$repo" = "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git" ]; then \
                git clone --recursive --depth=1 "$repo" || true; \
            else \
                git clone --depth=1 "$repo" || true; \
            fi; \
            if [ -f "$repo_dir/requirements.txt" ]; then \
                pip install --no-cache-dir -r "$repo_dir/requirements.txt" || true; \
            fi; \
            if [ -f "$repo_dir/install.py" ]; then \
                python "$repo_dir/install.py" || true; \
            fi; \
        fi; \
    done

# Create an unprivileged user to avoid root-owned files on mounted volumes
RUN useradd -m -u 1000 -s /bin/bash comfy && \
    chown -R comfy:comfy ${WORKSPACE} ${COMFYUI_DIR} /usr/local && \
    mkdir -p ${WORKSPACE}/inputs ${WORKSPACE}/outputs && \
    chown -R comfy:comfy ${WORKSPACE}

# Add scripts
COPY --chown=comfy:comfy bin/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=comfy:comfy scripts/ /opt/scripts/
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    chmod +x /opt/scripts/*.sh && \
    chown -R comfy:comfy /opt/scripts

EXPOSE 8188 8888 8090

WORKDIR ${COMFYUI_DIR}

# Basic healthcheck for ComfyUI HTTP
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
  CMD curl -fsS http://127.0.0.1:${COMFYUI_PORT}/ || exit 1

USER comfy

ENTRYPOINT ["/usr/bin/tini", "-s", "-g", "--", "/usr/local/bin/entrypoint.sh"]


