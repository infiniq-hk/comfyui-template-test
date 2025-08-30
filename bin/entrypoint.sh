#!/usr/bin/env bash
set -euo pipefail

# Required env (set defaults where possible)
: "${WORKSPACE:=/workspace}"
: "${COMFYUI_DIR:=/opt/ComfyUI}"
: "${MODELS_DIR:=/workspace/models}"

# Tokens (optional)
: "${civitai_token:=}"
: "${HF_TOKEN:=}"

export HF_HOME="${HF_HOME:-${WORKSPACE}/.cache/huggingface}"
mkdir -p "${HF_HOME}" "${MODELS_DIR}"

if [[ -n "${HF_TOKEN}" ]]; then
  mkdir -p ~/.huggingface
  echo "{"token":"${HF_TOKEN}"}" > ~/.huggingface/token
fi

# Optional: clone popular/custom nodes from env var CUSTOM_NODES (comma-separated repo URLs)
if [[ -n "${CUSTOM_NODES:-}" ]]; then
  IFS=',' read -ra repos <<< "${CUSTOM_NODES}"
  for repo in "${repos[@]}"; do
    name=$(basename "${repo}" .git)
    dest="${COMFYUI_DIR}/custom_nodes/${name}"
    if [[ ! -d "${dest}" ]]; then
      git clone --depth=1 "${repo}" "${dest}" || true
    fi
  done
fi

# Downloads via helper scripts
if [[ -n "${CHECKPOINT_IDS_TO_DOWNLOAD:-}" || -n "${LORAS_IDS_TO_DOWNLOAD:-}" || -n "${VAE_IDS_TO_DOWNLOAD:-}" || -n "${CONTROLNET_IDS_TO_DOWNLOAD:-}" || -n "${EMBEDDING_IDS_TO_DOWNLOAD:-}" || -n "${UPSCALER_IDS_TO_DOWNLOAD:-}" || \
      -n "${CHECKPOINT_VERSION_IDS_TO_DOWNLOAD:-}" || -n "${LORAS_VERSION_IDS_TO_DOWNLOAD:-}" || -n "${VAE_VERSION_IDS_TO_DOWNLOAD:-}" || -n "${CONTROLNET_VERSION_IDS_TO_DOWNLOAD:-}" || -n "${EMBEDDING_VERSION_IDS_TO_DOWNLOAD:-}" || -n "${UPSCALER_VERSION_IDS_TO_DOWNLOAD:-}" ]]; then
  CIVITAI_TOKEN_ENV="${civitai_token:-}"
  /opt/scripts/download_civitai.sh "${CIVITAI_TOKEN_ENV}" \
    "${CHECKPOINT_IDS_TO_DOWNLOAD:-}" \
    "${LORAS_IDS_TO_DOWNLOAD:-}" \
    "${VAE_IDS_TO_DOWNLOAD:-}" \
    "${CONTROLNET_IDS_TO_DOWNLOAD:-}" \
    "${EMBEDDING_IDS_TO_DOWNLOAD:-}" \
    "${UPSCALER_IDS_TO_DOWNLOAD:-}" \
    "${CHECKPOINT_VERSION_IDS_TO_DOWNLOAD:-}" \
    "${LORAS_VERSION_IDS_TO_DOWNLOAD:-}" \
    "${VAE_VERSION_IDS_TO_DOWNLOAD:-}" \
    "${CONTROLNET_VERSION_IDS_TO_DOWNLOAD:-}" \
    "${EMBEDDING_VERSION_IDS_TO_DOWNLOAD:-}" \
    "${UPSCALER_VERSION_IDS_TO_DOWNLOAD:-}"
fi

if [[ -n "${HF_REPOS_TO_DOWNLOAD:-}" || -n "${HF_FILES_TO_DOWNLOAD:-}" ]]; then
  /opt/scripts/download_hf.sh "${HF_TOKEN:-}" \
    "${HF_REPOS_TO_DOWNLOAD:-}" \
    "${HF_FILES_TO_DOWNLOAD:-}"
fi

# Start optional services
if [[ "${ENABLE_JUPYTER:-false}" == "true" ]]; then
  echo "Starting JupyterLab on port 8888..."
  jupyter lab --no-browser --ip=0.0.0.0 --port=8888 --NotebookApp.token='' --notebook-dir="${WORKSPACE}" &
fi

if [[ "${ENABLE_FILEBROWSER:-false}" == "true" ]]; then
  echo "Starting FileBrowser on port 8090..."
  filebrowser -r "${WORKSPACE}" -a 0.0.0.0 -p 8090 &
fi

# Start ComfyUI
cd "${COMFYUI_DIR}"

# Optionally fetch a default workflow JSON if provided
if [[ -n "${DEFAULT_WORKFLOW_URL:-}" ]]; then
  mkdir -p "${WORKSPACE}/workflows"
  curl -fsSL "${DEFAULT_WORKFLOW_URL}" -o "${WORKSPACE}/workflows/default.json" || true
fi

exec python main.py --listen 0.0.0.0 --port 8188 --output-directory "${WORKSPACE}/outputs" --input-directory "${WORKSPACE}/inputs"


