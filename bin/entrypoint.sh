#!/usr/bin/env bash
set -eo pipefail

# Required env (set defaults where possible)
: "${WORKSPACE:=/workspace}"
: "${COMFYUI_DIR:=/opt/ComfyUI}"
: "${MODELS_DIR:=/workspace/models}"

# Tokens (optional) - accept both uppercase and lowercase
: "${civitai_token:=${CIVITAI_TOKEN:-}}"
: "${HF_TOKEN:=}"

# Service control
: "${ENABLE_JUPYTER:=true}"
: "${ENABLE_FILEBROWSER:=false}"
: "${ENABLE_API:=true}"

export HF_HOME="${HF_HOME:-${WORKSPACE}/.cache/huggingface}"
mkdir -p "${HF_HOME}" "${MODELS_DIR}" "${WORKSPACE}/inputs" "${WORKSPACE}/outputs"

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
echo "[DEBUG] CIVITAI_VERSION_IDS_TO_DOWNLOAD='${CIVITAI_VERSION_IDS_TO_DOWNLOAD:-}'"
echo "[DEBUG] civitai_token length: ${#civitai_token}"

# Merge VERSION_* env vars for backward compatibility
_ckpt_ids="${CIVITAI_VERSION_IDS_TO_DOWNLOAD:-}${CIVITAI_VERSION_IDS_TO_DOWNLOAD:+,}${CHECKPOINT_VERSION_IDS_TO_DOWNLOAD:-}"
_lora_ids="${LORA_VERSION_IDS_TO_DOWNLOAD:-}${LORA_VERSION_IDS_TO_DOWNLOAD:+,}${LORAS_VERSION_IDS_TO_DOWNLOAD:-}"
_vae_ids="${VAE_VERSION_IDS_TO_DOWNLOAD:-}${VAE_VERSION_IDS_TO_DOWNLOAD:+,}${VAE_IDS_TO_DOWNLOAD:-}"
_ctrl_ids="${CONTROLNET_VERSION_IDS_TO_DOWNLOAD:-}${CONTROLNET_VERSION_IDS_TO_DOWNLOAD:+,}${CONTROLNET_IDS_TO_DOWNLOAD:-}"
_emb_ids="${EMBEDDING_VERSION_IDS_TO_DOWNLOAD:-}${EMBEDDING_VERSION_IDS_TO_DOWNLOAD:+,}${EMBEDDING_IDS_TO_DOWNLOAD:-}"
_up_ids="${UPSCALER_VERSION_IDS_TO_DOWNLOAD:-}${UPSCALER_VERSION_IDS_TO_DOWNLOAD:+,}${UPSCALER_IDS_TO_DOWNLOAD:-}"

# Define model categories and their IDs
declare -A MODEL_CATEGORIES=(
    ["${MODELS_DIR}/checkpoints"]="${_ckpt_ids}"
    ["${MODELS_DIR}/loras"]="${_lora_ids}"
    ["${MODELS_DIR}/vae"]="${_vae_ids}"
    ["${MODELS_DIR}/controlnet"]="${_ctrl_ids}"
    ["${MODELS_DIR}/embeddings"]="${_emb_ids}"
    ["${MODELS_DIR}/upscale_models"]="${_up_ids}"
)

# Ensure directories exist and schedule downloads
for TARGET_DIR in "${!MODEL_CATEGORIES[@]}"; do
    mkdir -p "$TARGET_DIR"
    MODEL_IDS_STRING="${MODEL_CATEGORIES[$TARGET_DIR]}"

    # Skip if empty
    if [[ -z "$MODEL_IDS_STRING" ]]; then
        continue
    fi

    IFS=',' read -ra MODEL_IDS <<< "$MODEL_IDS_STRING"

    for MODEL_ID in "${MODEL_IDS[@]}"; do
        MODEL_ID=$(echo "$MODEL_ID" | xargs)  # Trim whitespace
        if [[ -n "$MODEL_ID" ]]; then
            echo "🚀 Scheduling download: $MODEL_ID to $TARGET_DIR"
            (python3 /opt/scripts/download_with_aria.py -m "$MODEL_ID" -t "${civitai_token}" -o "$TARGET_DIR") &
        fi
    done
done

echo "[INFO] All Civitai downloads scheduled"

# HuggingFace downloads
if [[ -n "${HF_REPOS_TO_DOWNLOAD:-}" || -n "${HF_FILES_TO_DOWNLOAD:-}" ]]; then
  set +e
  /opt/scripts/download_hf.sh "${HF_TOKEN:-}" \
    "${HF_REPOS_TO_DOWNLOAD:-}" \
    "${HF_FILES_TO_DOWNLOAD:-}" || echo "[warn] Hugging Face downloads encountered errors; continuing"
  set -e
fi

# Start optional services
if [[ "${ENABLE_JUPYTER:-false}" == "true" ]]; then
  echo "Starting JupyterLab on port 8888..."
  nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
    --NotebookApp.token='' --NotebookApp.password='' \
    --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True \
    --notebook-dir="${WORKSPACE}" > /workspace/jupyter.log 2>&1 &
fi

if [[ "${ENABLE_FILEBROWSER:-false}" == "true" ]]; then
  echo "Starting FileBrowser on port 8090..."
  # Create noauth config for FileBrowser
  mkdir -p ~/.filebrowser
  echo '{"auth":{"method":"noauth"}}' > ~/.filebrowser/config.json
  nohup filebrowser -r "${WORKSPACE}" -a 0.0.0.0 -p 8090 -c ~/.filebrowser/config.json > /tmp/filebrowser.log 2>&1 &
fi

# Start ComfyUI in background
cd "${COMFYUI_DIR}"
echo "Starting ComfyUI on port ${COMFYUI_PORT:-8188}..."

# Optionally fetch a default workflow JSON if provided
if [[ -n "${DEFAULT_WORKFLOW_URL:-}" ]]; then
  mkdir -p "${WORKSPACE}/workflows"
  curl -fsSL "${DEFAULT_WORKFLOW_URL}" -o "${WORKSPACE}/workflows/default.json" || true
fi

nohup python main.py --listen "${LISTEN_HOST:-0.0.0.0}" --port "${COMFYUI_PORT:-8188}" \
  --output-directory "${WORKSPACE}/outputs" --input-directory "${WORKSPACE}/inputs" ${COMFYUI_EXTRA_ARGS:-} \
  > /workspace/comfyui.log 2>&1 &

# Wait for ComfyUI to start
echo "[INFO] Waiting for ComfyUI to initialize..."
for i in {1..30}; do
  if curl -sf "http://127.0.0.1:${COMFYUI_PORT:-8188}/" >/dev/null 2>&1; then
    echo "[INFO] ComfyUI is ready"
    break
  fi
  sleep 2
done

# Start FastAPI serverless endpoint if enabled
if [[ "${ENABLE_API:-false}" == "true" ]]; then
  echo "Starting FastAPI serverless endpoint on port ${API_PORT:-8000}..."
  cd /opt/serverless
  exec uvicorn api:app --host 0.0.0.0 --port "${API_PORT:-8000}" --log-level info
else
  echo "[INFO] API disabled. ComfyUI running in background."
  # Keep container alive
  tail -f /workspace/comfyui.log
fi