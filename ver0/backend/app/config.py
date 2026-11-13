"""앱 전역 설정. .env 파일에서 값을 읽는다."""
import logging
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger("todaysfilm")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # ─── 환경 ───
    # dev | production. production 이면 보안 검증이 강화된다 (아래 validate()).
    app_env: str = "dev"

    # ─── DB ───
    # [운영 전환] Supabase PostgreSQL 사용 시: postgresql://... (개발 PRD 2장)
    database_url: str = "sqlite:///./todaysfilm.db"

    # ─── 인증 ───
    # [운영 전환] Supabase Auth 로 교체 시 security.py/deps.py 만 수정하면 된다.
    jwt_secret: str = "dev-secret-change-me"
    jwt_expires_minutes: int = 60 * 24 * 30  # 30일

    # ─── 대화 암호화 (개발 PRD 8장: reflection_messages.text 암호화 저장) ───
    # Fernet 키. 생성: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
    # 비어 있으면 평문 저장 (개발 편의). 운영 모드에서는 필수.
    encryption_key: str = ""

    # ─── CORS ───
    # 운영에서는 쉼표로 도메인 지정 (예: https://todaysfilm.app,https://www.todaysfilm.app)
    cors_origins: str = "*"

    # ─── AI ★모델 교체 지점★ ───────────────────────────
    # "gemini" | "mock". 새 프로바이더(Claude 등)는 app/ai/factory.py 에 등록.
    ai_provider: str = "gemini"
    gemini_api_key: str = ""
    gemini_question_model: str = "gemini-2.5-flash"       # 질문/Vision 맥락 (고빈도·저비용)
    gemini_film_model: str = "gemini-2.5-flash"           # 결과물 생성 (문체 품질)
    gemini_embedding_model: str = "gemini-embedding-001"  # 기억 포인트 임베딩

    # LLM 호출 안정성 (개발 PRD 7장: 결과물 생성 실패 시 재시도)
    ai_timeout_seconds: float = 30.0   # 호출 1회 제한 시간
    ai_max_retries: int = 1            # 실패 시 재시도 횟수

    # ─── 서비스 정책 ───
    max_questions: int = 3                   # 질문 상한 — 서버 로직에서 강제 (개발 PRD 6.2)
    max_consecutive_skips: int = 2           # 연속 건너뛰기 → 조기 종료 (서비스 PRD 9 예외 흐름)
    max_regenerations_per_question: int = 3  # "질문 다시 받기" 한도 (비용 가드레일, PRD 외 유지 기능)
    max_answer_length: int = 2000            # 답변 최대 길이
    max_photos_per_film: int = 3             # MVP: 1~3장 (개발 PRD 5장 /films/start)

    # ─── 사진 저장 ───
    # [운영 전환] Supabase Storage 사용 시 services/storage.py 만 교체.
    upload_dir: str = "./uploads"
    photo_max_upload_mb: int = 40      # 업로드 용량 제한 (고화질 원본 대응)
    photo_max_side_storage: int = 2048 # 서버 저장본 리사이즈 (EXIF 제거 겸 재인코딩, 개발 PRD 8장)
    photo_max_side_for_ai: int = 1024  # Vision 전송용 리사이즈 (비용 절감)

    # ─── 위치/날씨 (3차 확장) ───
    weather_enabled: bool = True  # Open-Meteo 조회. 테스트에서는 false 로 외부 호출 차단

    # ─── Rate Limit (비용/어뷰징 가드레일) ───
    rate_limit_llm_per_hour: int = 60
    rate_limit_auth_per_hour: int = 20  # 로그인/가입 브루트포스 방지 (IP당)

    # ─── 과거 기록 연결 (개발 PRD 6.4) ───
    # 기억 포인트 코사인 유사도가 이 값 이상일 때만 회상 후보 (정밀도 우선)
    recall_threshold: float = 0.55
    # 최소 며칠 이상 지난 기록만 회상 대상으로 삼는다
    recall_min_days_apart: int = 7

    @property
    def is_production(self) -> bool:
        return self.app_env.lower() == "production"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    def validate_for_production(self) -> None:
        """운영 모드 기동 시 위험한 기본값을 차단한다."""
        if not self.is_production:
            return
        problems = []
        if self.jwt_secret == "dev-secret-change-me" or len(self.jwt_secret) < 32:
            problems.append("JWT_SECRET 이 기본값이거나 너무 짧습니다 (32자 이상 랜덤 문자열 필요)")
        if self.cors_origins == "*":
            problems.append("CORS_ORIGINS 가 '*' 입니다. 운영 도메인을 지정하세요")
        if not self.encryption_key:
            problems.append("ENCRYPTION_KEY 가 없습니다. 대화 암호화 저장은 운영 필수입니다 (개발 PRD 8장)")
        if self.database_url.startswith("sqlite"):
            logger.warning("운영 환경에서 SQLite 사용 중 — PostgreSQL(Supabase) 전환을 권장합니다")
        if problems:
            raise RuntimeError("운영 설정 오류:\n- " + "\n- ".join(problems))


@lru_cache
def get_settings() -> Settings:
    return Settings()
