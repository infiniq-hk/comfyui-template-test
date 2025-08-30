## ComfyUI on RunPod with Civitai & Hugging Face

This image runs ComfyUI on RunPod, persists models in `/workspace/models`, and can download models from Civitai and Hugging Face using environment variables.

### Build

```bash
docker build -t comfyui-runpod:latest .
```

### Run (local test)

```bash
docker run --gpus all -it --rm -p 8188:8188 \
  -e civitai_token=YOUR_CIVITAI_TOKEN \
  -e CHECKPOINT_IDS_TO_DOWNLOAD=1081768 \
  -e LORAS_IDS_TO_DOWNLOAD=135867 \
  -e HF_TOKEN=YOUR_HF_TOKEN \
  -e HF_REPOS_TO_DOWNLOAD="runwayml/stable-diffusion-v1-5" \
  -v ${PWD}/workspace:/workspace \
  comfyui-runpod:latest
```

Then open `http://localhost:8188`.

### RunPod Template Tips

- Volume Mount Path: `/workspace`
- Expose HTTP Ports: `8188,8888` (8188 is ComfyUI)
- Environment variables:
  - `civitai_token`: API key for Civitai downloads. See the REST docs: [Public REST API](https://developer.civitai.com/docs/api/public-rest)
  - `CHECKPOINT_IDS_TO_DOWNLOAD`: comma-separated Civitai model IDs for checkpoints
  - `LORAS_IDS_TO_DOWNLOAD`: comma-separated Civitai model IDs for LoRAs
  - `VAE_IDS_TO_DOWNLOAD`: comma-separated Civitai model IDs for VAEs
  - `CONTROLNET_IDS_TO_DOWNLOAD`: comma-separated Civitai model IDs for ControlNet models
  - `EMBEDDING_IDS_TO_DOWNLOAD`: comma-separated Civitai model IDs for text embeddings
  - `UPSCALER_IDS_TO_DOWNLOAD`: comma-separated Civitai model IDs for upscalers
  - `CHECKPOINT_VERSION_IDS_TO_DOWNLOAD`: comma-separated Civitai model VERSION IDs for checkpoints
  - `LORAS_VERSION_IDS_TO_DOWNLOAD`: comma-separated VERSION IDs for LoRAs
  - `VAE_VERSION_IDS_TO_DOWNLOAD`: comma-separated VERSION IDs for VAEs
  - `CONTROLNET_VERSION_IDS_TO_DOWNLOAD`: comma-separated VERSION IDs for ControlNet models
  - `EMBEDDING_VERSION_IDS_TO_DOWNLOAD`: comma-separated VERSION IDs for embeddings
  - `UPSCALER_VERSION_IDS_TO_DOWNLOAD`: comma-separated VERSION IDs for upscalers
  - `HF_TOKEN`: optional token for private HF repos; see [Hugging Face docs](https://huggingface.co/docs)
  - `HF_REPOS_TO_DOWNLOAD`: comma-separated repo IDs to snapshot
  - `HF_FILES_TO_DOWNLOAD`: comma-separated `repo:path` specs to fetch a single file
  - `CUSTOM_NODES`: comma-separated git URLs for ComfyUI custom nodes to clone
  - `DEFAULT_WORKFLOW_URL`: optional URL to a workflow JSON to pre-load into `/workspace/workflows/default.json`
  - `ENABLE_JUPYTER`: set to "true" to start JupyterLab on port 8888
  - `ENABLE_FILEBROWSER`: set to "true" to start FileBrowser on port 8090

Models are stored in:

- `/workspace/models/checkpoints`
- `/workspace/models/loras`
- `/workspace/models/vae`
 - `/workspace/models/controlnet`
 - `/workspace/models/embeddings`
 - `/workspace/models/upscale_models`

The container symlinks `ComfyUI/models` → `/workspace/models` so everything persists across restarts.

### Notes

- Civitai downloads use `downloadUrl` with `?token=` when provided per the official API. See [Civitai Public REST API](https://developer.civitai.com/docs/api/public-rest).
- Hugging Face downloads use `huggingface_hub` snapshot/file APIs; see [Hugging Face Docs](https://huggingface.co/docs).

### Preinstalled custom nodes

- `ComfyUI-Manager`
- `comfyui_controlnet_aux`
- `ComfyUI_Noise`

### Workflow templates

- If `DEFAULT_WORKFLOW_URL` is set, it will download to `/workspace/workflows/default.json` on startup.


