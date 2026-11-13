"""프로바이더 팩토리. ★모델 교체 지점★

새 프로바이더 추가 절차:
  1. app/ai/claude.py 등에 AIProvider 구현체 작성 (gemini.py 복사해서 시작)
  2. 아래 get_ai_provider() 에 분기 추가
  3. .env 에서 AI_PROVIDER=claude 로 변경
"""
from functools import lru_cache

from ..config import get_settings
from .base import AIProvider
from .mock import MockProvider


@lru_cache
def get_ai_provider() -> AIProvider:
    settings = get_settings()
    provider = settings.ai_provider.lower()

    if provider == "gemini" and settings.gemini_api_key:
        from .gemini import GeminiProvider

        return GeminiProvider(
            api_key=settings.gemini_api_key,
            question_model=settings.gemini_question_model,
            film_model=settings.gemini_film_model,
            embedding_model=settings.gemini_embedding_model,
        )

    # if provider == "claude" and settings.anthropic_api_key:      # ← Claude 전환 시
    #     from .claude import ClaudeProvider
    #     return ClaudeProvider(...)

    # 키가 없거나 mock 지정 시: 개발용 mock
    return MockProvider()
