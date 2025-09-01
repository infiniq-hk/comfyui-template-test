#!/usr/bin/env python3
"""
CivitAI model downloader with aria2/curl.
- Uses token ONLY for API metadata fetch
- No Authorization header on CDN (pre-signed) file URLs
- Accepts BOTH version IDs and model IDs (resolves latest version with files)
"""
import argparse
import os
import sys
import subprocess
import requests

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124 Safari/537.36"
)
REFERER = "https://civitai.com"


def parse_args():
    parser = argparse.ArgumentParser(description="Download models from CivitAI")
    parser.add_argument("-m", "--model", required=True, help="model ID or version ID")
    parser.add_argument("-o", "--output", default=".", help="output directory")
    parser.add_argument("-t", "--token", help="CivitAI token (optional; env CIVITAI_TOKEN/civitai_token also used)")
    parser.add_argument("--filename", help="override filename")
    return parser.parse_args()


def get_token(args):
    """Get token from args or environment (optional)."""
    return args.token or os.getenv("CIVITAI_TOKEN") or os.getenv("civitai_token")


def _api_get(url, token):
    headers = {"User-Agent": USER_AGENT}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    r = requests.get(url, headers=headers, timeout=30)
    if r.status_code == 404:
        return None
    r.raise_for_status()
    return r.json()


def resolve_version(model_or_version_id, token):
    """Resolve input as version first; if not found try model -> pick first version with files."""
    ver = _api_get(f"https://civitai.com/api/v1/model-versions/{model_or_version_id}", token)
    if ver:
        return ver

    model = _api_get(f"https://civitai.com/api/v1/models/{model_or_version_id}", token)
    if not model:
        sys.exit(f"❌ ID {model_or_version_id} not found as version or model")

    versions = model.get("modelVersions") or []
    chosen = None
    for v in versions:
        if v.get("files"):
            chosen = v
            break
    if not chosen and versions:
        chosen = versions[0]
    if not chosen:
        sys.exit(f"❌ Model {model_or_version_id} has no versions with files")

    chosen["model"] = {"name": model.get("name", "model")}
    return chosen


def get_download_info(ver, fallback_id, custom_filename=None):
    # URL
    url = ver.get("downloadUrl")
    if not url:
        files = ver.get("files") or []
        primary = None
        for f in files:
            if f.get("primary") and f.get("downloadUrl"):
                primary = f
                break
        if not primary and files:
            primary = files[0]
        url = primary.get("downloadUrl") if primary else None
    if not url:
        sys.exit("❌ No downloadUrl in version")

    # Filename
    if custom_filename:
        name = custom_filename
    else:
        name = None
        files = ver.get("files") or []
        if files:
            name = files[0].get("name")
        if not name and ver.get("model"):
            model_name = ver["model"].get("name", "model").replace(" ", "_")
            name = f"{model_name}_v{ver.get('id', fallback_id)}.safetensors"
        if not name:
            name = f"model_v{fallback_id}.safetensors"
    return url, name


def download_with_aria2(url, output_dir, filename):
    os.makedirs(output_dir, exist_ok=True)
    dst = os.path.join(output_dir, filename)

    if os.path.exists(dst) and os.path.getsize(dst) > 2 * 1024 * 1024:
        print(f"✔ exists: {filename}")
        return True

    cmd = [
        "aria2c",
        "-x", "8", "-s", "8", "-k", "1M",
        "--continue=true",
        "--dir", output_dir,
        "-o", filename,
        "--console-log-level=warn",
        "--summary-interval=5",
        "--header", f"User-Agent: {USER_AGENT}",
        "--header", f"Referer: {REFERER}",
        url,
    ]
    return subprocess.run(cmd).returncode == 0


def download_with_curl(url, output_dir, filename):
    os.makedirs(output_dir, exist_ok=True)
    dst = os.path.join(output_dir, filename)
    cmd = [
        "curl", "-L", "-#", "-C", "-",
        "-H", f"User-Agent: {USER_AGENT}",
        "-H", f"Referer: {REFERER}",
        "-o", dst,
        url,
    ]
    return subprocess.run(cmd).returncode == 0


def main():
    args = parse_args()
    token = get_token(args)

    ver = resolve_version(args.model, token)
    url, filename = get_download_info(ver, args.model, args.filename)

    print(f"↓ {filename} → {args.output}")
    if download_with_aria2(url, args.output, filename) or download_with_curl(url, args.output, filename):
        print(f"✅ downloaded: {filename}")
    else:
        sys.exit("❌ download failed")


if __name__ == "__main__":
    main()
