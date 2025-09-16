"""
FastAPI serverless endpoint for ComfyUI
Provides POST /generate endpoint that queues jobs and returns results
"""
import os
import uuid
import asyncio
from typing import Dict, Any, Optional, List
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import uvicorn

from comfy_client import ComfyClient


# Initialize FastAPI app
app = FastAPI(
    title="ComfyUI Serverless API",
    description="Generate images using ComfyUI workflows",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize ComfyUI client
comfy = ComfyClient(
    host=f"http://127.0.0.1:{os.getenv('COMFYUI_PORT', '8188')}",
    timeout=int(os.getenv('COMFY_TIMEOUT', '600'))
)


# Request/Response models
class GenerateRequest(BaseModel):
    prompt: str = Field(..., description="Text prompt for generation")
    negative_prompt: str = Field("", description="Negative prompt")
    width: int = Field(832, ge=512, le=2048, description="Image width")
    height: int = Field(1216, ge=512, le=2048, description="Image height")
    steps: int = Field(28, ge=1, le=100, description="Sampling steps")
    cfg_scale: float = Field(6.5, ge=1.0, le=30.0, description="CFG scale")
    seed: Optional[int] = Field(None, description="Random seed (auto-generated if not provided)")
    checkpoint: str = Field("bigLove_photo1.3.safetensors", description="Checkpoint model to use")
    workflow_type: str = Field("default", description="Workflow type: default, anime, photoreal")


class GenerateResponse(BaseModel):
    job_id: str
    status: str
    outputs: List[Dict[str, str]] = []
    error: Optional[str] = None


# Basic workflow template (SDXL)
def create_workflow(params: GenerateRequest) -> Dict[str, Any]:
    """Create a ComfyUI workflow from parameters"""
    
    # Generate seed if not provided
    seed = params.seed if params.seed is not None else int.from_bytes(os.urandom(4), 'big')
    
    workflow = {
        "1": {
            "inputs": {"ckpt_name": params.checkpoint},
            "class_type": "CheckpointLoaderSimple"
        },
        "2": {
            "inputs": {
                "width": params.width,
                "height": params.height,
                "batch_size": 1
            },
            "class_type": "EmptyLatentImage"
        },
        "3": {
            "inputs": {"text": params.prompt},
            "class_type": "CLIPTextEncode"
        },
        "4": {
            "inputs": {"text": params.negative_prompt},
            "class_type": "CLIPTextEncode"
        },
        "5": {
            "inputs": {
                "seed": seed,
                "steps": params.steps,
                "cfg": params.cfg_scale,
                "sampler_name": "euler",
                "scheduler": "normal",
                "denoise": 1.0,
                "model": ["1", 0],
                "positive": ["3", 0],
                "negative": ["4", 0],
                "latent_image": ["2", 0]
            },
            "class_type": "KSampler"
        },
        "6": {
            "inputs": {
                "samples": ["5", 0],
                "vae": ["1", 2]
            },
            "class_type": "VAEDecode"
        },
        "7": {
            "inputs": {"images": ["6", 0]},
            "class_type": "SaveImage"
        }
    }
    
    return workflow


@app.get("/")
async def root():
    """Health check endpoint"""
    return {"status": "ok", "service": "ComfyUI Serverless API"}


@app.get("/health")
async def health():
    """Detailed health check"""
    comfy_healthy = comfy.health_check()
    
    return {
        "status": "healthy" if comfy_healthy else "unhealthy",
        "comfyui": "ok" if comfy_healthy else "error",
        "timestamp": int(asyncio.get_event_loop().time())
    }


@app.post("/generate", response_model=GenerateResponse)
async def generate_image(request: GenerateRequest):
    """Generate an image using ComfyUI"""
    
    # Check if ComfyUI is healthy
    if not comfy.health_check():
        raise HTTPException(status_code=503, detail="ComfyUI service unavailable")
    
    try:
        # Create workflow from parameters
        workflow = create_workflow(request)
        
        # Submit to ComfyUI
        prompt_id = comfy.post_prompt(workflow)
        
        # Wait for completion
        result = comfy.wait_for_completion(prompt_id)
        
        # Extract outputs
        outputs = comfy.extract_outputs(result)
        
        return GenerateResponse(
            job_id=prompt_id,
            status="completed",
            outputs=outputs
        )
        
    except TimeoutError:
        raise HTTPException(status_code=408, detail="Generation timeout")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Generation failed: {str(e)}")


@app.get("/queue")
async def get_queue():
    """Get current ComfyUI queue status"""
    try:
        queue_info = comfy.get_queue()
        return queue_info
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get queue: {str(e)}")


@app.get("/history/{prompt_id}")
async def get_history(prompt_id: str):
    """Get execution history for a specific job"""
    try:
        history = comfy.get_history(prompt_id)
        return history
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get history: {str(e)}")


if __name__ == "__main__":
    # For development
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=int(os.getenv("API_PORT", "8000")),
        log_level="info"
    )
