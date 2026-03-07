"""FastAPI application for nemo agent backend."""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import logging
from typing import Optional

from src.utils.config import get_settings

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="nemo Agent API",
    description="LangGraph-based agent backend for nemo macOS application",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost", "http://127.0.0.1"],
    allow_credentials=True,
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


# === Request / Response Models ===

class Message(BaseModel):
    role: str = Field(..., description="'user', 'assistant', or 'system'")
    content: str = Field(..., description="Message content")


class ToolCall(BaseModel):
    tool_name: str
    arguments: str
    result: str


class ChatRequest(BaseModel):
    conversation_id: str = Field(..., description="UUID of the conversation")
    messages: list[Message] = Field(..., description="Conversation history")
    model_id: str = Field(default="openai/gpt-4")


class ChatResponse(BaseModel):
    content: str
    tool_calls: Optional[list[ToolCall]] = None


# === Endpoints ===

@app.get("/")
async def root():
    return {"status": "ok", "service": "nemo-agent", "version": "0.1.0"}


@app.get("/health")
async def health_check():
    settings = get_settings()
    return {
        "status": "healthy",
        "checks": {
            "api": "ok",
            "api_key": "ok" if settings.has_api_key else "missing",
            "agent": "not_implemented",  # Week 2で実装
        }
    }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest) -> ChatResponse:
    """
    Chat endpoint with LangGraph agent.
    Week 1: minimal echo implementation.
    Week 2: full LangGraph integration.
    """
    settings = get_settings()
    
    # APIキーチェック
    if not settings.has_api_key:
        raise HTTPException(
            status_code=401,
            detail="API key not configured. Set it in nemo Settings."
        )
    
    logger.info(f"Chat request: conversation={request.conversation_id}, messages={len(request.messages)}")
    
    last_message = request.messages[-1] if request.messages else None
    if not last_message:
        raise HTTPException(status_code=400, detail="No messages provided")
    
    # TODO: Week 2 - LangGraphエージェントに置き換え
    return ChatResponse(
        content=(
            f"Hello from nemo-agent! Received: '{last_message.content}'. "
            "LangGraph integration coming in Week 2!"
        ),
        tool_calls=None
    )


@app.post("/chat/stream")
async def chat_stream(request: ChatRequest):
    """Streaming endpoint - Week 5で実装"""
    raise HTTPException(status_code=501, detail="Coming in Week 5!")


if __name__ == "__main__":
    import uvicorn
    settings = get_settings()
    uvicorn.run(app, host=settings.host, port=settings.port)
