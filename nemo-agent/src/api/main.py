"""FastAPI application for nemo agent backend."""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import logging
from typing import Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="nemo Agent API",
    description="LangGraph-based agent backend for nemo macOS application",
    version="0.1.0",
)

# CORS configuration for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict this
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class Message(BaseModel):
    """Single message in conversation."""
    role: str = Field(..., description="Message role: 'user', 'assistant', or 'system'")
    content: str = Field(..., description="Message content")


class ToolCall(BaseModel):
    """Tool call information."""
    tool_name: str = Field(..., description="Name of the tool that was called")
    arguments: str = Field(..., description="JSON string of tool arguments")
    result: str = Field(..., description="Result returned by the tool")


class ChatRequest(BaseModel):
    """Request model for chat endpoint."""
    conversation_id: str = Field(..., description="UUID of the conversation")
    messages: list[Message] = Field(..., description="Conversation history")
    model_id: str = Field(default="openai/gpt-4", description="Model to use for completion")


class ChatResponse(BaseModel):
    """Response model for chat endpoint."""
    content: str = Field(..., description="Agent's response content")
    tool_calls: Optional[list[ToolCall]] = Field(
        default=None,
        description="List of tools called during execution"
    )


@app.get("/")
async def root():
    """Health check endpoint."""
    return {
        "status": "ok",
        "service": "nemo-agent",
        "version": "0.1.0"
    }


@app.get("/health")
async def health_check():
    """Detailed health check."""
    return {
        "status": "healthy",
        "checks": {
            "api": "ok",
            "agent": "not_implemented",  # Will be updated in Week 2
        }
    }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest) -> ChatResponse:
    """
    Handle chat request with LangGraph agent.
    
    This is a minimal implementation for Week 1.
    Full LangGraph integration will be added in Week 2.
    """
    logger.info(f"Received chat request for conversation: {request.conversation_id}")
    logger.info(f"Message count: {len(request.messages)}")
    
    try:
        # TODO: Week 2 - Replace with actual LangGraph agent call
        # For now, return a simple echo response
        
        last_message = request.messages[-1] if request.messages else None
        
        if not last_message:
            raise HTTPException(status_code=400, detail="No messages provided")
        
        response_content = (
            f"Hello from nemo-agent! I received your message: '{last_message.content}'. "
            "LangGraph integration coming in Week 2!"
        )
        
        return ChatResponse(
            content=response_content,
            tool_calls=None  # Will be populated when tools are integrated
        )
        
    except Exception as e:
        logger.error(f"Error processing chat request: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.post("/chat/stream")
async def chat_stream(request: ChatRequest):
    """
    Streaming version of chat endpoint.
    
    Returns Server-Sent Events (SSE) stream.
    Will be implemented in Week 5.
    """
    raise HTTPException(
        status_code=501,
        detail="Streaming endpoint not yet implemented. Coming in Week 5!"
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
