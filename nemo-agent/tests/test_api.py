"""Tests for FastAPI endpoints."""

import pytest
from fastapi.testclient import TestClient
from src.api.main import app

client = TestClient(app)


def test_root():
    """Test root endpoint."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["service"] == "nemo-agent"


def test_health_check():
    """Test health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "checks" in data


def test_chat_basic():
    """Test basic chat endpoint."""
    request_data = {
        "conversation_id": "test-uuid-123",
        "messages": [
            {"role": "user", "content": "Hello"}
        ],
        "model_id": "openai/gpt-4"
    }
    
    response = client.post("/chat", json=request_data)
    assert response.status_code == 200
    
    data = response.json()
    assert "content" in data
    assert isinstance(data["content"], str)
    assert len(data["content"]) > 0


def test_chat_no_messages():
    """Test chat endpoint with no messages."""
    request_data = {
        "conversation_id": "test-uuid-456",
        "messages": [],
        "model_id": "openai/gpt-4"
    }
    
    response = client.post("/chat", json=request_data)
    assert response.status_code == 400


def test_chat_stream_not_implemented():
    """Test that streaming endpoint returns not implemented."""
    request_data = {
        "conversation_id": "test-uuid-789",
        "messages": [
            {"role": "user", "content": "Stream test"}
        ]
    }
    
    response = client.post("/chat/stream", json=request_data)
    assert response.status_code == 501
