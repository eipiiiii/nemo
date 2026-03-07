# nemo-agent

LangGraph-based agent backend for nemo macOS application.

## Architecture

This service provides a REST API that handles agent logic using LangGraph.
The Swift macOS UI communicates with this service via HTTP.

```
Swift UI (nemo) <--HTTP--> FastAPI <--> LangGraph Agent
```

**自動起動**: nemo macOS アプリを起動すると、このサーバーが自動的にバックグラウンドで起動します。

## Setup

### Requirements

- Python 3.11+
- Poetry (推奨) or pip

### Quick Setup

```bash
cd nemo-agent
chmod +x setup.sh
./setup.sh
```

セットアップスクリプトが以下を自動実行します：
1. Python バージョン確認
2. 依存パッケージのインストール（Poetry または pip）
3. `.env` ファイルの作成

### Manual Installation

#### Using Poetry (推奨)

```bash
cd nemo-agent
poetry install

# .env を作成
cp .env.example .env
# .env を編集してAPIキーを設定
```

#### Using pip

```bash
cd nemo-agent

# 仮想環境作成
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 依存パッケージインストール
pip install langgraph langchain langchain-openai fastapi uvicorn[standard] pydantic python-dotenv aiosqlite

# .env を作成
cp .env.example .env
# .env を編集してAPIキーを設定
```

### Configuration

`.env` ファイルを編集：

```bash
# OpenAI API Key
OPENAI_API_KEY=sk-...

# または OpenRouter
OPENROUTER_API_KEY=sk-or-v1-...
```

## Running

### 自動起動（推奨）

nemo macOS アプリを起動すると、サーバーが自動的に起動します。
手動での起動は不要です。

### 手動起動（開発用）

```bash
# Poetry の場合
poetry run uvicorn src.api.main:app --reload --port 8000

# pip + venv の場合
source venv/bin/activate
python -m uvicorn src.api.main:app --reload --port 8000
```

API documentation:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Testing

```bash
# Poetry
poetry run pytest

# pip + venv
source venv/bin/activate
pytest
```

## Troubleshooting

### Swift アプリから "Server failed to start" エラーが出る

1. Python 3.11+ がインストールされているか確認：
   ```bash
   python3 --version
   ```

2. 依存パッケージがインストールされているか確認：
   ```bash
   cd nemo-agent
   ./setup.sh
   ```

3. 手動起動で動作確認：
   ```bash
   cd nemo-agent
   poetry run uvicorn src.api.main:app --port 8000
   ```

4. Xcode のコンソールでログを確認：
   - `[PythonServer]` タグでサーバーのログが表示されます

### Port 8000 が既に使用されている

別のプロセスが 8000 番ポートを使っている場合：

```bash
# ポートを使用しているプロセスを確認
lsof -i :8000

# プロセスを終了
kill -9 <PID>
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
├── setup.sh                 # セットアップスクリプト
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

### GET /health

Health check endpoint.

## Development Roadmap

- [x] Week 1: Project setup + minimal FastAPI
- [x] Auto-start server from Swift app
- [ ] Week 2: LangGraph basic graph (plan/act/reflect)
- [ ] Week 3: Tool integration (migrate from Swift ToolService)
- [ ] Week 4: Swift API client integration
- [ ] Week 5: Streaming support + error handling
- [ ] Week 6: Testing + documentation + Docker
