# nemo-agent

LangGraph-based agent backend for nemo macOS application.

## Architecture

This service provides a REST API that handles agent logic using LangGraph.
The Swift macOS UI communicates with this service via HTTP.

```
Swift UI (nemo) <--HTTP--> FastAPI <--> LangGraph Agent
```

## Setup

### Requirements

- Python 3.11+
- Poetry (推奨) or pip

### Installation

```bash
cd nemo-agent

# Using Poetry
poetry install

# Using pip
pip install -r requirements.txt
```

### Configuration

Create `.env` file:

```bash
OPENAI_API_KEY=your_openai_api_key_here
# or use OpenRouter
OPENROUTER_API_KEY=your_openrouter_api_key_here
```

## Running

```bash
# Development mode with auto-reload
poetry run uvicorn src.api.main:app --reload --port 8000

# Or using Python directly
python -m uvicorn src.api.main:app --reload --port 8000
```

API documentation will be available at:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Testing

```bash
poetry run pytest
```

## Project Structure

```
nemo-agent/
├── src/
│   ├── api/
│   │   └── main.py          # FastAPI application
│   ├── agent/
│   │   ├── graph.py         # LangGraph state graph
│   │   ├── nodes.py         # Graph node implementations
│   │   └── tools.py         # LangChain tools
│   ├── models/
│   │   └── schemas.py       # Pydantic models
│   └── utils/
│       └── config.py        # Configuration management
├── tests/
│   ├── test_api.py
│   └── test_agent.py
├── pyproject.toml
├── .env.example
└── README.md
```

## API Endpoints

### POST /chat

Send a message and get agent response.

**Request:**
```json
{
  "conversation_id": "uuid-string",
  "messages": [
    {"role": "user", "content": "Hello"}
  ],
  "model_id": "openai/gpt-4"
}
```

**Response:**
```json
{
  "content": "Agent response text",
  "tool_calls": [
    {
      "tool_name": "get_current_time",
      "arguments": "{}",
      "result": "2026-03-07T21:30:00"
    }
  ]
}
```

### POST /chat/stream

Streaming version of chat endpoint (Server-Sent Events).

## Development Roadmap

- [x] Week 1: Project setup + minimal FastAPI
- [ ] Week 2: LangGraph basic graph (plan/act/reflect)
- [ ] Week 3: Tool integration (migrate from Swift ToolService)
- [ ] Week 4: Swift API client integration
- [ ] Week 5: Streaming support + error handling
- [ ] Week 6: Testing + documentation + Docker
