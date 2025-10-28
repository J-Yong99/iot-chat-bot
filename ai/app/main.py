import os
import asyncio
from typing import List, Optional, Dict, Any

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from starlette.responses import StreamingResponse

OLLAMA_BASE = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434").rstrip("/")
DEFAULT_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2:3b")
CORS_ORIGINS = [o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",")]
AUTOPULL = os.getenv("OLLAMA_AUTOPULL", "false").lower() == "true"

app = FastAPI(title="FastAPI x Ollama")

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS if CORS_ORIGINS != ["*"] else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ------------------ Pydantic models ------------------ #
class ChatMessage(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    messages: List[ChatMessage]
    model: Optional[str] = None
    stream: bool = False
    options: Dict[str, Any] = Field(default_factory=dict)

class GenerateRequest(BaseModel):
    messages: List[ChatMessage]
    model: Optional[str] = None
    stream: bool = False
    options: Dict[str, Any] = Field(default_factory=dict)

class EmbeddingRequest(BaseModel):
    prompt: str
    model: Optional[str] = None

async def _ollama_get(path: str):
    async with httpx.AsyncClient(timeout=10) as s:
        r = await s.get(f"{OLLAMA_BASE}{path}")
        r.raise_for_status()
        return r.json()
async def _ollama_post(path: str, json: dict, stream: bool = False):
    if not stream:
        async with httpx.AsyncClient(timeout=None) as s:
            r = await s.post(f"{OLLAMA_BASE}{path}", json=json)
            r.raise_for_status()
            return r.json()
        
    else:
        async def gen():
            async with httpx.AsyncClient(timeout=None) as s:
                async with s.stream("POST", f"{OLLAMA_BASE}{path}", json=json) as r:
                    r.raise_for_status()
                    async for line in r.aiter_lines():
                        if not line:
                            continue
                        yield line + "\n"
        return StreamingResponse(gen(), media_type="application/x-ndjson")
    
async def wait_for_ollama(max_wait: int = 60):
    deadline = asyncio.get_event_loop().time() + max_wait
    last_err = None
    while asyncio.get_event_loop().time() < deadline:
        try:
            await _ollama_get("/api/tags")
            return True
        except Exception as e:
            last_err = e
            await asyncio.sleep(2)
    print(f"[warn] Ollama not ready: {last_err}")
    return False

async def autopull_model(model: str):
    try:
        payload = {"name" : model}
        async with httpx.AsyncClient(timeout=None) as s:
            async with s.stream("POST", f"{OLLAMA_BASE}/api/pull", json=payload) as r:
                r.raise_for_status()
                async for _ in r.aiter_lines():
                    pass
        print(f"[info] Pulled model: {model}")
    except Exception as e:
        print(f"[warn] autopull failed: {e}")

@app.on_event("startup")   # ✅ 밑줄 제거
async def _startup():
    ready = await wait_for_ollama()
    if AUTOPULL and ready:
        await autopull_model(DEFAULT_MODEL)

@app.get("/healthz")
async def healthz():
    try:
        await _ollama_get("/api/tags")
        return {"ok": True, "ollama": OLLAMA_BASE}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))
    
@app.post("/chat")
async def chat(req: ChatRequest):
    payload = {
        "model" : req.model or DEFAULT_MODEL,
        "messages" : [m.model_dump() for m in req.messages],
        "stream" : req.stream,
    }
    if req.options:
        payload["options"] = req.options
    resp = await _ollama_post("/api/chat", json=payload, stream=req.stream)
    return resp

@app.post("/generate")
async def generate(req: GenerateRequest):
    payload = {
        "model" : req.model or DEFAULT_MODEL,
        "prompt" : req.prompt,
        "stream" : req.stream,
    }
    if req.options:
        payload["options"] = req.options
    resp = await _ollama_post("/api/generate", json=payload, stream=req.stream)
    return resp

@app.post("/embeddings")
async def embeddings(req: EmbeddingRequest):
    payload = {
        "model" : req.model or "nomic-embed-text",
        "prompt" : req.prompt
    }
    resp = await _ollama_post("/api/embeddings", json=payload, stream=False)
    return resp
        