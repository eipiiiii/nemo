"""Configuration management for nemo-agent.

API keys are injected from Swift Keychain via environment variables.
No .env file required when running through the nemo macOS app.
"""

import os
from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # === API Keys ===
    # Swift側のKeychainから自動注入される (PythonServerManager.swift参照)
    # 手動起動時は .env ファイルまたは環境変数で設定
    openrouter_api_key: str = Field(default="", alias="OPENROUTER_API_KEY")
    openai_api_key: str = Field(default="", alias="OPENAI_API_KEY")

    # === Model Configuration ===
    default_model: str = Field(
        default="openai/gpt-4",
        alias="DEFAULT_MODEL"
    )

    # === Agent Configuration ===
    max_iterations: int = Field(default=10, alias="MAX_ITERATIONS")
    timeout_seconds: int = Field(default=300, alias="TIMEOUT_SECONDS")

    # === Database ===
    checkpoint_db_path: str = Field(
        default="./agent_state.db",
        alias="CHECKPOINT_DB_PATH"
    )

    # === Server ===
    host: str = Field(default="127.0.0.1", alias="HOST")
    port: int = Field(default=8000, alias="PORT")

    model_config = {
        "env_file": ".env",           # 手動起動時は .env を参照
        "env_file_encoding": "utf-8",
        "populate_by_name": True,
        "extra": "ignore",
    }

    @property
    def has_api_key(self) -> bool:
        """有効なAPIキーが設定されているか確認"""
        return bool(self.openrouter_api_key or self.openai_api_key)

    @property
    def active_api_key(self) -> str:
        """優先順位に従って有効なAPIキーを返す"""
        return self.openrouter_api_key or self.openai_api_key


@lru_cache
def get_settings() -> Settings:
    """Cached settings instance."""
    return Settings()
