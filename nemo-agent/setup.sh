#!/bin/bash
# Setup script for nemo-agent

set -e

echo "Setting up nemo-agent..."

# Check Python version
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    echo "Please install Python 3.11 or later from https://www.python.org/"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
REQUIRED_VERSION="3.11"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo "Error: Python $REQUIRED_VERSION or later is required (found $PYTHON_VERSION)"
    exit 1
fi

echo "✓ Python $PYTHON_VERSION found"

# Check if Poetry is installed
if command -v poetry &> /dev/null; then
    echo "✓ Poetry found"
    echo "Installing dependencies with Poetry..."
    poetry install
else
    echo "Poetry not found. Installing dependencies with pip..."
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        echo "Creating virtual environment..."
        python3 -m venv venv
    fi
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install dependencies
    echo "Installing dependencies..."
    pip install langgraph langchain langchain-openai fastapi uvicorn[standard] pydantic python-dotenv aiosqlite
    pip install --dev pytest pytest-asyncio httpx black ruff
    
    echo "✓ Dependencies installed in virtual environment"
    echo "  To activate: source venv/bin/activate"
fi

# Setup .env if it doesn't exist
if [ ! -f ".env" ]; then
    echo "Creating .env from template..."
    cp .env.example .env
    echo "⚠️  Please edit .env and add your API keys"
else
    echo "✓ .env already exists"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "To start the server manually:"
if command -v poetry &> /dev/null; then
    echo "  poetry run uvicorn src.api.main:app --reload --port 8000"
else
    echo "  source venv/bin/activate"
    echo "  python -m uvicorn src.api.main:app --reload --port 8000"
fi
echo ""
echo "Or just run the nemo macOS app - it will start the server automatically!"
