"""오늘의 필름 백엔드 엔트리포인트.

실행 (개발):  uvicorn app.main:app --reload
실행 (운영):  APP_ENV=production uvicorn app.main:app --host 0.0.0.0 --port 8000
문서:  http://localhost:8000/docs
"""
import logging
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from .config import get_settings
from .database import Base, SessionLocal, engine, run_light_migrations
from .routers import archive, auth, moments, photos, records, reports, share, voice

# ─── 로깅 ───────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("todaysfilm")

settings = get_settings()
settings.validate_for_production()  # 운영 모드면 위험한 기본값 차단

# MVP: 테이블 자동 생성 + sqlite 경량 마이그레이션 (database.run_light_migrations).
# 스키마가 자주 바뀌기 시작하면 Alembic 도입 권장.
Base.metadata.create_all(bind=engine)
run_light_migrations()

app = FastAPI(
    title="오늘의 필름 API",
    description="하루 회고형 AI 사진 회고 서비스 백엔드",
    version="1.0.0",
    # 운영에서는 API 문서 비공개 (내부 개발자만 dev 환경에서 확인)
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,  # .env 의 CORS_ORIGINS
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── 요청 로깅 미들웨어 (요청 ID + 소요 시간) ──────────
@app.middleware("http")
async def request_logging(request: Request, call_next):
    request_id = uuid.uuid4().hex[:8]
    start = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        logger.exception("[%s] %s %s → unhandled", request_id, request.method, request.url.path)
        raise
    elapsed_ms = (time.perf_counter() - start) * 1000
    # 헬스체크는 로그 소음이라 제외
    if request.url.path != "/health":
        logger.info(
            "[%s] %s %s → %d (%.0fms)",
            request_id, request.method, request.url.path,
            response.status_code, elapsed_ms,
        )
    response.headers["X-Request-Id"] = request_id
    return response


# ─── 전역 예외 처리 (내부 정보 비노출) ─────────────────
@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.exception("unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": "일시적인 오류가 발생했어요. 잠시 후 다시 시도해 주세요."},
    )


from .ai.base import AIUnavailableError  # noqa: E402


@app.exception_handler(AIUnavailableError)
async def ai_unavailable_handler(request: Request, exc: AIUnavailableError):
    """LLM 장애는 서버 잘못이 아님을 구분해 502 + 친절한 안내로 응답."""
    logger.error("AI provider unavailable: %s", exc)
    return JSONResponse(
        status_code=502,
        content={"detail": "AI 응답이 늦어지고 있어요. 잠시 후 다시 시도해 주세요."},
    )


# ─── 라우터 ─────────────────────────────────────────
app.include_router(auth.router)
app.include_router(photos.router)
app.include_router(records.router)
app.include_router(archive.router)
app.include_router(moments.router)   # 순간 기록
app.include_router(voice.router)     # 음성 입력 (STT)
app.include_router(reports.router)   # 월간/연간 리포트
app.include_router(share.router)     # [FUTURE] 필름 공유 링크

Path(settings.upload_dir).mkdir(parents=True, exist_ok=True)
# 주의: 업로드 사진은 더 이상 정적 서빙하지 않는다.
# 사적 데이터이므로 인증된 GET /photos/{id}/file 로만 접근 가능 (routers/photos.py).


@app.get("/health", tags=["system"])
def health():
    from .ai.factory import get_ai_provider

    # DB 연결 확인 (로드밸런서 헬스체크용)
    db_ok = True
    try:
        with SessionLocal() as db:
            db.execute(text("SELECT 1"))
    except Exception:
        db_ok = False

    return {
        "status": "ok" if db_ok else "degraded",
        "db": db_ok,
        "ai_provider": type(get_ai_provider()).__name__,
        "env": settings.app_env,
    }
