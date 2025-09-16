"""
ComfyUI HTTP API client for serverless workflows
Based on ComfyUI's REST API endpoints
"""
import json
import time
import requests
from typing import Any, Dict, List, Optional


class ComfyClient:
    def __init__(self, host: str = "http://127.0.0.1:8188", timeout: int = 600):
        self.base = host.rstrip("/")
        self.timeout = timeout

    def post_prompt(self, prompt: Dict[str, Any]) -> str:
        """Submit a prompt to ComfyUI and return the prompt ID"""
        response = requests.post(
            f"{self.base}/prompt", 
            json={"prompt": prompt}, 
            timeout=30
        )
        response.raise_for_status()
        return response.json()["prompt_id"]

    def get_history(self, prompt_id: str) -> Dict[str, Any]:
        """Get execution history for a specific prompt ID"""
        response = requests.get(
            f"{self.base}/history/{prompt_id}", 
            timeout=15
        )
        response.raise_for_status()
        return response.json()

    def get_queue(self) -> Dict[str, Any]:
        """Get current queue status"""
        response = requests.get(f"{self.base}/queue", timeout=15)
        response.raise_for_status()
        return response.json()

    def wait_for_completion(self, prompt_id: str) -> Dict[str, Any]:
        """Wait for a prompt to complete and return the result"""
        start_time = time.time()
        
        while True:
            if time.time() - start_time > self.timeout:
                raise TimeoutError(f"ComfyUI job timeout after {self.timeout}s")
            
            try:
                history = self.get_history(prompt_id)
                
                if prompt_id in history:
                    result = history[prompt_id]
                    status = result.get("status", {})
                    
                    if status.get("completed", False):
                        return result
                    elif "error" in status:
                        raise RuntimeError(f"ComfyUI error: {status['error']}")
                
                time.sleep(1)
                
            except requests.RequestException as e:
                # Retry on network errors
                time.sleep(2)
                continue

    def extract_outputs(self, result: Dict[str, Any]) -> List[Dict[str, str]]:
        """Extract output files from ComfyUI result"""
        outputs = []
        
        for node_id, node_data in result.get("outputs", {}).items():
            # Handle image outputs
            for img in node_data.get("images", []):
                outputs.append({
                    "type": "image",
                    "filename": img["filename"],
                    "subfolder": img.get("subfolder", ""),
                    "node_id": node_id
                })
            
            # Handle video outputs (if any)
            for vid in node_data.get("videos", []):
                outputs.append({
                    "type": "video", 
                    "filename": vid["filename"],
                    "subfolder": vid.get("subfolder", ""),
                    "node_id": node_id
                })
        
        return outputs

    @staticmethod
    def load_workflow(path: str) -> Dict[str, Any]:
        """Load a workflow JSON file"""
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)

    def health_check(self) -> bool:
        """Check if ComfyUI is responding"""
        try:
            response = requests.get(f"{self.base}/", timeout=5)
            return response.status_code == 200
        except:
            return False
