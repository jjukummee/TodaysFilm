"""간단한 슬라이딩 윈도우 rate limiter.

LLM 호출 엔드포인트(비용)와 인증 엔드포인트(브루트포스)를 보호한다.

[한계/업그레이드] 프로세스 메모리 기반이라 단일 워커에서만 정확하다.
uvicorn --workers N 또는 다중 인스턴스 배포 시 Redis 기반
(예: fastapi-limiter)으로 교체할 것 — 이 파일만 바꾸면 된다.
"""
import time
from collections import defaultdict, deque

from fastapi import Depends, HTTPException, Request, status

from .config import get_settings
from .deps import get_current_user
from .models import User

# key → 최근 요청 타임스탬프 큐
_buckets: dict[str, deque[float]] = defaultdict(deque)
WINDOW_SECONDS = 3600.0


def _allow(key: str, limit: int) -> bool:
    now = time.monotonic()
    bucket = _buckets[key]
    while bucket and now - bucket[0] > WINDOW_SECONDS:
        bucket.popleft()
    if len(bucket) >= limit:
        return False
    bucket.append(now)
    return True


def llm_rate_limit(user: User = Depends(get_current_user)) -> User:
    """LLM 호출 엔드포인트용 — 사용자당 시간당 제한. 통과 시 user 반환."""
    settings = get_settings()
    if not _allow(f"llm:{user.id}", settings.rate_limit_llm_per_hour):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.",
        )
    return user


def auth_rate_limit(request: Request) -> None:
    """로그인/가입용 — IP당 시간당 제한 (브루트포스 방지)."""
    settings = get_settings()
    ip = request.client.host if request.client else "unknown"
    if not _allow(f"auth:{ip}", settings.rate_limit_auth_per_hour):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "시도가 너무 많아요. 잠시 후 다시 시도해 주세요.",
        )
