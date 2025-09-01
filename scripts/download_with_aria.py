#!/usr/bin/env python3
"""
CivitAI model downloader with aria2 - based on Hearmeman24's approach
"""
import requests
import argparse
import os
import sys
import subprocess
import json

def parse_args():
    parser = argparse.ArgumentParser(description="Download models from CivitAI")
    parser.add_argument("-m", "--model", type=str, required=True, 
                      help="CivitAI model version ID to download")
    parser.add_argument("-t", "--token", type=str, 
                      help="CivitAI API token (if not set in environment)")
    parser.add_argument("-o", "--output", type=str, default=".", 
                      help="Output directory")
    parser.add_argument("--filename", type=str, 
                      help="Override filename")
    return parser.parse_args()

def get_token(args):
    """Get token from args or environment"""
    token = args.token or os.getenv("civitai_token") or os.getenv("CIVITAI_TOKEN")
    if not token:
        print("❌ Error: No CivitAI token provided!")
        print("   Set CIVITAI_TOKEN environment variable or use --token")
        sys.exit(1)
    return token

def fetch_model_info(model_id, token):
    """Fetch model metadata from CivitAI API"""
    url = f"https://civitai.com/api/v1/model-versions/{model_id}"
    headers = {"Authorization": f"Bearer {token}"}
    
    print(f"🔍 Fetching metadata for model version {model_id}...")
    
    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"❌ API request failed: {e}")
        sys.exit(1)

def get_download_info(data, model_id, custom_filename=None):
    """Extract download URL and filename from API response"""
    # Get download URL
    download_url = data.get('downloadUrl')
    if not download_url:
        print("❌ No downloadUrl found in API response")
        sys.exit(1)
    
    # Determine filename
    if custom_filename:
        filename = custom_filename
    else:
        filename = None
        # Try to get from files array
        if 'files' in data and data['files']:
            filename = data['files'][0].get('name')
        
        # Fallback to model name
        if not filename and 'model' in data:
            model_name = data['model'].get('name', 'model').replace(' ', '_')
            filename = f"{model_name}_v{model_id}.safetensors"
        
        # Final fallback
        if not filename:
            filename = f"model_v{model_id}.safetensors"
    
    return download_url, filename

def download_with_aria2(url, filename, token, output_dir):
    """Download file using aria2c with resume support"""
    os.makedirs(output_dir, exist_ok=True)
    filepath = os.path.join(output_dir, filename)
    
    # Check if file already exists
    if os.path.exists(filepath):
        size_mb = os.path.getsize(filepath) / (1024 * 1024)
        if size_mb > 10:  # If larger than 10MB, assume it's complete
            print(f"✅ File already exists: {filename} ({size_mb:.1f}MB)")
            return True
        else:
            print(f"🗑️ Removing incomplete file: {filename} ({size_mb:.1f}MB)")
            os.remove(filepath)
    
    print(f"📥 Downloading: {filename}")
    print(f"📁 Output directory: {output_dir}")
    
    # Build aria2c command
    cmd = [
        "aria2c",
        "-x", "16",              # 16 connections
        "-s", "16",              # 16 splits
        "-k", "1M",              # 1MB chunks
        "--continue=true",       # Resume downloads
        "--dir", output_dir,     # Output directory
        "-o", filename,          # Output filename
        "--console-log-level=warn",  # Less verbose
        "--summary-interval=5",      # Progress every 5 seconds
        "--header", f"Authorization: Bearer {token}",
        url
    ]
    
    try:
        # Run aria2c
        result = subprocess.run(cmd)
        
        if result.returncode == 0:
            print(f"✅ Successfully downloaded: {filename}")
            return True
        else:
            print(f"❌ Download failed with aria2c (exit code: {result.returncode})")
            return False
            
    except FileNotFoundError:
        print("⚠️ aria2c not found. Please install aria2.")
        print("   Ubuntu/Debian: sudo apt-get install aria2")
        print("   macOS: brew install aria2")
        return False

def main():
    args = parse_args()
    token = get_token(args)
    
    # Fetch model info
    data = fetch_model_info(args.model, token)
    
    # Get download details
    download_url, filename = get_download_info(data, args.model, args.filename)
    
    # Download the file
    success = download_with_aria2(download_url, filename, token, args.output)
    
    if not success:
        print("\n💡 Falling back to curl...")
        # Fallback to curl
        filepath = os.path.join(args.output, filename)
        cmd = [
            "curl", "-L", "-#",
            "-H", f"Authorization: Bearer {token}",
            "-o", filepath,
            download_url
        ]
        result = subprocess.run(cmd)
        if result.returncode == 0:
            print(f"✅ Successfully downloaded with curl: {filename}")
        else:
            print(f"❌ Download failed")
            sys.exit(1)

if __name__ == "__main__":
    main()
