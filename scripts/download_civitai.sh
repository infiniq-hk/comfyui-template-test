#!/usr/bin/env bash
set -euo pipefail

# Usage: download_civitai.sh <TOKEN> <CHECKPOINT_IDS> <LORA_IDS> <VAE_IDS> <CONTROLNET_IDS> <EMBEDDING_IDS> <UPSCALER_IDS> \
#                                    <CHECKPOINT_VERSION_IDS> <LORA_VERSION_IDS> <VAE_VERSION_IDS> <CONTROLNET_VERSION_IDS> <EMBEDDING_VERSION_IDS> <UPSCALER_VERSION_IDS>

TOKEN="${1:-}"
CHECKPOINT_IDS="${2:-}"
LORA_IDS="${3:-}"
VAE_IDS="${4:-}"
CONTROLNET_IDS="${5:-}"
EMBEDDING_IDS="${6:-}"
UPSCALER_IDS="${7:-}"

# Optional: model VERSION IDs per type
CHECKPOINT_VERSION_IDS="${8:-}"
LORA_VERSION_IDS="${9:-}"
VAE_VERSION_IDS="${10:-}"
CONTROLNET_VERSION_IDS="${11:-}"
EMBEDDING_VERSION_IDS="${12:-}"
UPSCALER_VERSION_IDS="${13:-}"

API="https://civitai.com/api/v1/models"
API_VERSIONS="https://civitai.com/api/v1/model-versions"
MODELS_ROOT="${MODELS_DIR:-/workspace/models}"

mkdir -p \
  "${MODELS_ROOT}/checkpoints" \
  "${MODELS_ROOT}/loras" \
  "${MODELS_ROOT}/vae" \
  "${MODELS_ROOT}/controlnet" \
  "${MODELS_ROOT}/embeddings" \
  "${MODELS_ROOT}/upscale_models"

_download_by_model_id() {
  local model_id="$1" subdir="$2"
  local url="${API}/${model_id}"
  if [[ -n "${TOKEN}" ]]; then
    url="${url}?token=${TOKEN}"
  fi
  echo "Fetching ${url}"
  json=$(curl -fsSL "${url}")
  # pick first primary file's downloadUrl
  downloadUrl=$(echo "${json}" | python - <<'PY'
import sys, json
data=json.load(sys.stdin)
items=data.get('modelVersions',[])
for v in items:
  files=v.get('files',[])
  for f in files:
    if f.get('primary') and f.get('downloadUrl'):
      print(f['downloadUrl'])
      sys.exit(0)
  if files:
    u=files[0].get('downloadUrl')
    if u:
      print(u)
      sys.exit(0)
print("")
PY
)
  if [[ -z "${downloadUrl}" ]]; then
    echo "No download URL for model ${model_id}" >&2
    return 0
  fi
  if [[ -n "${TOKEN}" ]]; then
    if [[ "${downloadUrl}" != *"?token="* ]]; then
      downloadUrl="${downloadUrl}?token=${TOKEN}"
    fi
  fi
  echo "Downloading model ${model_id} to ${subdir}"
  cd "${MODELS_ROOT}/${subdir}"
  aria2c -x16 -s16 -k1M --continue=true "${downloadUrl}" || curl -fLo "model_${model_id}" "${downloadUrl}"
}

_download_by_version_id() {
  local version_id="$1" subdir="$2"
  local url="${API_VERSIONS}/${version_id}"
  if [[ -n "${TOKEN}" ]]; then
    url="${url}?token=${TOKEN}"
  fi
  echo "Fetching ${url}"
  json=$(curl -fsSL "${url}")
  # pick primary file's downloadUrl or fallback to first
  downloadUrl=$(echo "${json}" | python - <<'PY'
import sys, json
data=json.load(sys.stdin)
files=data.get('files', [])
for f in files:
  if f.get('primary') and f.get('downloadUrl'):
    print(f['downloadUrl'])
    sys.exit(0)
if files:
  u=files[0].get('downloadUrl')
  if u:
    print(u)
    sys.exit(0)
print("")
PY
)
  if [[ -z "${downloadUrl}" ]]; then
    echo "No download URL for version ${version_id}" >&2
    return 0
  fi
  if [[ -n "${TOKEN}" ]]; then
    if [[ "${downloadUrl}" != *"?token="* ]]; then
      downloadUrl="${downloadUrl}?token=${TOKEN}"
    fi
  fi
  echo "Downloading version ${version_id} to ${subdir}"
  cd "${MODELS_ROOT}/${subdir}"
  aria2c -x16 -s16 -k1M --continue=true "${downloadUrl}" || curl -fLo "model_version_${version_id}" "${downloadUrl}"
}

IFS=',' read -ra ckpt_ids <<< "${CHECKPOINT_IDS}"
for id in "${ckpt_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_model_id "${id}" "checkpoints"
done

IFS=',' read -ra lora_ids <<< "${LORA_IDS}"
for id in "${lora_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_model_id "${id}" "loras"
done

IFS=',' read -ra vae_ids <<< "${VAE_IDS}"
for id in "${vae_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_model_id "${id}" "vae"
done

# Version ID downloads per type (optional)
IFS=',' read -ra ckpt_ver_ids <<< "${CHECKPOINT_VERSION_IDS}"
for id in "${ckpt_ver_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_version_id "${id}" "checkpoints"
done

IFS=',' read -ra lora_ver_ids <<< "${LORA_VERSION_IDS}"
for id in "${lora_ver_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_version_id "${id}" "loras"
done

IFS=',' read -ra vae_ver_ids <<< "${VAE_VERSION_IDS}"
for id in "${vae_ver_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_version_id "${id}" "vae"
done

IFS=',' read -ra controlnet_ver_ids <<< "${CONTROLNET_VERSION_IDS}"
for id in "${controlnet_ver_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_version_id "${id}" "controlnet"
done

IFS=',' read -ra embedding_ver_ids <<< "${EMBEDDING_VERSION_IDS}"
for id in "${embedding_ver_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_version_id "${id}" "embeddings"
done

IFS=',' read -ra upscaler_ver_ids <<< "${UPSCALER_VERSION_IDS}"
for id in "${upscaler_ver_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_version_id "${id}" "upscale_models"
done

IFS=',' read -ra controlnet_ids <<< "${CONTROLNET_IDS}"
for id in "${controlnet_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_model_id "${id}" "controlnet"
done

IFS=',' read -ra embedding_ids <<< "${EMBEDDING_IDS}"
for id in "${embedding_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_model_id "${id}" "embeddings"
done

IFS=',' read -ra upscaler_ids <<< "${UPSCALER_IDS}"
for id in "${upscaler_ids[@]:-}"; do
  [[ -z "${id}" ]] && continue
  _download_by_model_id "${id}" "upscale_models"
done

echo "Civitai downloads done"


