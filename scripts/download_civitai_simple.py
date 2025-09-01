#!/usr/bin/env python3
import requests
import argparse
import os
import sys
import subprocess

# Parse arguments
parser = argparse.ArgumentParser()
parser.add_argument("-m", "--model", type=str, required=True, help="CivitAI model version ID to download")
parser.add_argument("-t", "--token", type=str, help="CivitAI API token (if not set in environment)")
parser.add_argument("-d", "--dir", type=str, default=".", help="Directory to download to")
args = parser.parse_args()

# Determine the token
token = os.getenv("civitai_token", os.getenv("CIVITAI_TOKEN", args.token))
if not token:
    print("Error: no token provided. Set the 'civitai_token' environment variable or use --token.")
    sys.exit(1)

# URL of the file to download
url = f"https://civitai.com/api/v1/model-versions/{args.model}"

print(f"[INFO] Fetching metadata for version {args.model}...")

# Perform the request with Authorization header
headers = {"Authorization": f"Bearer {token}"}
response = requests.get(url, headers=headers)

if response.status_code == 200:
    data = response.json()
    
    # Get download URL and filename
    download_url = data.get('downloadUrl')
    if not download_url:
        print("Error: No downloadUrl found in response")
        sys.exit(1)
    
    # Try to get filename from files array or use default
    filename = None
    if 'files' in data and len(data['files']) > 0:
        filename = data['files'][0].get('name')
    
    if not filename and 'model' in data:
        model_name = data['model'].get('name', 'model')
        filename = f"{model_name}_v{args.model}.safetensors"
    
    if not filename:
        filename = f"model_v{args.model}.safetensors"
    
    # Change to target directory
    os.chdir(args.dir)
    
    # Download with aria2c
    print(f"[INFO] Downloading {filename} to {args.dir}")
    cmd = [
        "aria2c", "-x16", "-s16", "-k1M", "--continue=true",
        "--header", f"Authorization: Bearer {token}",
        "-o", filename,
        download_url
    ]
    
    result = subprocess.run(cmd, capture_output=False)
    
    if result.returncode == 0:
        print(f"[SUCCESS] Downloaded {filename}")
    else:
        # Fallback to curl
        print("[INFO] Trying with curl...")
        cmd = [
            "curl", "-L", "-H", f"Authorization: Bearer {token}",
            "-o", filename, download_url
        ]
        result = subprocess.run(cmd, capture_output=False)
        
        if result.returncode == 0:
            print(f"[SUCCESS] Downloaded {filename} (via curl)")
        else:
            print(f"[ERROR] Failed to download {filename}")
            sys.exit(1)
else:
    print(f"Error: API returned status {response.status_code}")
    print(f"Response: {response.text[:500]}")
    sys.exit(1)
