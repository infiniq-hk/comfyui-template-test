#!/usr/bin/env bash
set -eo pipefail

# Required env (set defaults where possible)
: "${WORKSPACE:=/workspace}"
: "${COMFYUI_DIR:=/opt/ComfyUI}"
: "${MODELS_DIR:=/workspace/models}"

# Tokens (optional) - accept both uppercase and lowercase
: "${civitai_token:=${CIVITAI_TOKEN:-}}"
: "${HF_TOKEN:=}"

export HF_HOME="${HF_HOME:-${WORKSPACE}/.cache/huggingface}"
mkdir -p "${HF_HOME}" "${MODELS_DIR}"

if [[ -n "${HF_TOKEN}" ]]; then
  mkdir -p ~/.huggingface
  echo "{\"token\":\"${HF_TOKEN}\"}" > ~/.huggingface/token
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

# Downloads via helper scripts (best-effort; never block startup)
echo "[INFO] Checking for Civitai downloads..."
echo "[DEBUG] CHECKPOINT_VERSION_IDS_TO_DOWNLOAD='${CHECKPOINT_VERSION_IDS_TO_DOWNLOAD:-}'"
echo "[DEBUG] civitai_token length: ${#civitai_token}"

# Simple Python-based downloads like Hearmeman24
echo "[INFO] Processing Civitai downloads..."

# Make download script executable
chmod +x /opt/scripts/download_civitai_simple.py

# Process checkpoint downloads
if [[ -n "${CHECKPOINT_VERSION_IDS_TO_DOWNLOAD:-}" ]]; then
  echo "[INFO] Downloading checkpoints..."
  IFS=',' read -ra IDS <<< "${CHECKPOINT_VERSION_IDS_TO_DOWNLOAD}"
  for id in "${IDS[@]}"; do
    [[ -z "$id" ]] && continue
    echo "Downloading checkpoint $id..."
    (cd "${MODELS_DIR}/checkpoints" && python3 /opt/scripts/download_civitai_simple.py -m "$id") &
  done
fi

# Process LoRA downloads
if [[ -n "${LORAS_VERSION_IDS_TO_DOWNLOAD:-}" ]]; then
  echo "[INFO] Downloading LoRAs..."
  IFS=',' read -ra IDS <<< "${LORAS_VERSION_IDS_TO_DOWNLOAD}"
  for id in "${IDS[@]}"; do
    [[ -z "$id" ]] && continue
    echo "Downloading LoRA $id..."
    (cd "${MODELS_DIR}/loras" && python3 /opt/scripts/download_civitai_simple.py -m "$id") &
  done
fi

# Process VAE downloads
if [[ -n "${VAE_VERSION_IDS_TO_DOWNLOAD:-}" ]]; then
  echo "[INFO] Downloading VAEs..."
  IFS=',' read -ra IDS <<< "${VAE_VERSION_IDS_TO_DOWNLOAD}"
  for id in "${IDS[@]}"; do
    [[ -z "$id" ]] && continue
    echo "Downloading VAE $id..."
    (cd "${MODELS_DIR}/vae" && python3 /opt/scripts/download_civitai_simple.py -m "$id") &
  done
fi

echo "[INFO] All downloads scheduled in background"

if [[ -n "${HF_REPOS_TO_DOWNLOAD:-}" || -n "${HF_FILES_TO_DOWNLOAD:-}" ]]; then
  set +e
  /opt/scripts/download_hf.sh "${HF_TOKEN:-}" \
    "${HF_REPOS_TO_DOWNLOAD:-}" \
    "${HF_FILES_TO_DOWNLOAD:-}" || echo "[warn] Hugging Face downloads encountered errors; continuing"
  set -e
fi

# Start optional services
if [[ "${ENABLE_JUPYTER:-false}" == "true" ]]; then
  echo "Starting JupyterLab..."
  # Simple approach like Hearmeman24
  if [ ! -f "/workspace/jupyter_${RUNPOD_POD_ID}_started" ]; then
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/workspace &
    touch "/workspace/jupyter_${RUNPOD_POD_ID}_started"
    echo "JupyterLab started on port 8888"
  else
    echo "JupyterLab already running"
  fi
fi

if [[ "${ENABLE_FILEBROWSER:-false}" == "true" ]]; then
  echo "Starting FileBrowser on port 8090..."
  # Create noauth config for FileBrowser
  mkdir -p ~/.filebrowser
  echo '{"auth":{"method":"noauth"}}' > ~/.filebrowser/config.json
  filebrowser -r "${WORKSPACE}" -a 0.0.0.0 -p 8090 -c ~/.filebrowser/config.json > /tmp/filebrowser.log 2>&1 &
fi

# Wait a bit for downloads to start (optional)
echo "[INFO] Waiting for downloads to initialize..."
sleep 5

# Start ComfyUI
cd "${COMFYUI_DIR}"

# Optionally fetch a default workflow JSON if provided
if [[ -n "${DEFAULT_WORKFLOW_URL:-}" ]]; then
  mkdir -p "${WORKSPACE}/workflows"
  curl -fsSL "${DEFAULT_WORKFLOW_URL}" -o "${WORKSPACE}/workflows/default.json" || true
fi

# Log download status
echo "[INFO] Download status:"
if [ -f /tmp/civitai_download.log ]; then
  tail -20 /tmp/civitai_download.log
fi

exec python main.py --listen "${LISTEN_HOST:-0.0.0.0}" --port "${COMFYUI_PORT:-8188}" \
  --output-directory "${WORKSPACE}/outputs" --input-directory "${WORKSPACE}/inputs" ${COMFYUI_EXTRA_ARGS:-}


