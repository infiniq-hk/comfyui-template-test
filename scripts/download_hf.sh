#!/usr/bin/env bash
set -uo pipefail

# Usage: download_hf.sh <HF_TOKEN> <REPOS_CSV> <FILES_CSV>
# - REPOS_CSV: comma-separated repo ids (e.g., "runwayml/stable-diffusion-v1-5,stabilityai/sd-vae-ft-mse")
# - FILES_CSV: comma-separated repo_id:path pairs (e.g., "user/repo:folder/file.safetensors")

HF_TOKEN="${1:-}"
REPOS="${2:-}"
FILES="${3:-}"

MODELS_ROOT="${MODELS_DIR:-/workspace/models}"
mkdir -p "${MODELS_ROOT}"

export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
export HF_HUB_ENABLE_HF_TRANSFER=1
  if [[ -n "${HF_TOKEN}" ]]; then
  mkdir -p ~/.huggingface
  echo "{\"token\":\"${HF_TOKEN}\"}" > ~/.huggingface/token
fi

_snapshot() {
  local repo="$1"
  echo "Snapshotting repo ${repo}"
  python - <<PY 2>/dev/null || echo "Failed to snapshot ${repo}"
try:
    from huggingface_hub import snapshot_download
    import os
    repo_id = "${repo}"
    local_dir = os.path.join("${MODELS_ROOT}", repo_id.replace('/', '__'))
    os.makedirs(local_dir, exist_ok=True)
    snapshot_download(repo_id=repo_id, local_dir=local_dir, local_dir_use_symlinks=False, resume_download=True, allow_patterns=None)
    print(local_dir)
except Exception as e:
    print(f"Error: {e}")
PY
}

_download_file() {
  local spec="$1"
  IFS=':' read -r repo path <<< "${spec}"
  [[ -z "${repo}" || -z "${path}" ]] && return 0
  echo "Downloading ${repo}:${path}"
  python - <<PY 2>/dev/null || echo "Failed to download ${repo}:${path}"
try:
    from huggingface_hub import hf_hub_download
    import os
    repo_id = "${repo}"
    filename = "${path}"
    local_dir = os.path.join("${MODELS_ROOT}", repo_id.replace('/', '__'))
    os.makedirs(local_dir, exist_ok=True)
    dst = hf_hub_download(repo_id=repo_id, filename=filename, local_dir=local_dir, local_dir_use_symlinks=False, resume_download=True)
    print(dst)
except Exception as e:
    print(f"Error: {e}")
PY
}

IFS=',' read -ra repos <<< "${REPOS}"
for r in "${repos[@]:-}"; do
  [[ -z "${r}" ]] && continue
  _snapshot "${r}"
done

IFS=',' read -ra files <<< "${FILES}"
for f in "${files[@]:-}"; do
  [[ -z "${f}" ]] && continue
  _download_file "${f}"
done

echo "Hugging Face downloads done"




