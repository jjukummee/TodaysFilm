"""DB 모델. PRD 9장 데이터 구조 기반.

하루 = 필름 1개 원칙: (user_id, date) 유니크 제약.
"""
import uuid
from datetime import date, datetime, timezone

from sqlalchemy import (
    Boolean, Date, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base
from .services.crypto import EncryptedText


def _uuid() -> str:
    return uuid.uuid4().hex


def _now() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    nickname: Mapped[str] = mapped_column(String(50))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    records: Mapped[list["DailyFilmRecord"]] = relationship(back_populates="user")


class DailyFilmRecord(Base):
    """하루 회고 기록의 기본 단위 (PRD 9.1)."""
    __tablename__ = "daily_film_records"
    __table_args__ = (UniqueConstraint("user_id", "date", name="uq_user_date"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    date: Mapped[date] = mapped_column(Date, index=True)

    # in_progress → completed (필름 생성 완료 시)
    status: Mapped[str] = mapped_column(String(20), default="in_progress")

    # "다시 꺼내지 않기" — 이 기록을 회상(과거 기록 연결) 대상에서 제외 (서비스 PRD 8.6·17장)
    recall_blocked: Mapped[bool] = mapped_column(Boolean, default=False)

    # ─── AI 생성 결과물 (PRD 7.4) ───
    film_title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    ending_narration: Mapped[str | None] = mapped_column(Text, nullable=True)
    representative_sentence: Mapped[str | None] = mapped_column(Text, nullable=True)

    # ─── 위치/날씨 기반 회고 보조 (3차) ───
    location_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    weather_summary: Mapped[str | None] = mapped_column(String(100), nullable=True)  # 예: "맑음, 27°C"

    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now)

    user: Mapped["User"] = relationship(back_populates="records")
    photos: Mapped[list["Photo"]] = relationship(back_populates="record", cascade="all, delete-orphan")
    questions: Mapped[list["AIQuestion"]] = relationship(
        back_populates="record", cascade="all, delete-orphan", order_by="AIQuestion.question_order"
    )
    answers: Mapped[list["UserAnswer"]] = relationship(back_populates="record", cascade="all, delete-orphan")
    keywords: Mapped[list["MemoryKeyword"]] = relationship(back_populates="record", cascade="all, delete-orphan")


class Photo(Base):
    """업로드된 사진. MVP는 로컬 디스크 저장 → 운영 전환 시 S3/Supabase Storage로 교체."""
    __tablename__ = "photos"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    record_id: Mapped[str | None] = mapped_column(ForeignKey("daily_film_records.id"), nullable=True, index=True)
    file_path: Mapped[str] = mapped_column(String(500))
    is_main: Mapped[bool] = mapped_column(Boolean, default=False)  # 대표 사진 (PRD 7.1)
    # Vision 맥락 JSON (개발 PRD 6.1) — 질문 단서용, 사용자에게 비노출 (API 응답에 넣지 말 것)
    ai_context: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    record: Mapped["DailyFilmRecord | None"] = relationship(back_populates="photos")


class AIQuestion(Base):
    """AI 질문 (PRD 9.2)."""
    __tablename__ = "ai_questions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    record_id: Mapped[str] = mapped_column(ForeignKey("daily_film_records.id"), index=True)
    question_order: Mapped[int] = mapped_column(Integer)
    question_text: Mapped[str] = mapped_column(EncryptedText)
    # photo_reason | moment_meaning | memory_point | self_reflection | film_metaphor | recall
    question_type: Mapped[str] = mapped_column(String(50))
    # recall형 질문이 가리키는 과거 기록 (개발 PRD 6.4 — 회고당 최대 1회 대체)
    recall_record_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    regeneration_count: Mapped[int] = mapped_column(Integer, default=0)  # 다시 받기 횟수 (가드레일)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    record: Mapped["DailyFilmRecord"] = relationship(back_populates="questions")
    answer: Mapped["UserAnswer | None"] = relationship(back_populates="question", uselist=False)


class UserAnswer(Base):
    """사용자 답변 (PRD 9.3). 건너뛰기도 기록으로 남긴다."""
    __tablename__ = "user_answers"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    question_id: Mapped[str] = mapped_column(ForeignKey("ai_questions.id"), unique=True)
    record_id: Mapped[str] = mapped_column(ForeignKey("daily_film_records.id"), index=True)
    answer_text: Mapped[str] = mapped_column(EncryptedText, default="")
    skipped: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now)

    question: Mapped["AIQuestion"] = relationship(back_populates="answer")
    record: Mapped["DailyFilmRecord"] = relationship(back_populates="answers")


class MemoryKeyword(Base):
    """과거 기록 연결용 키워드 (PRD 9.4).

    주의: 감정 관련 키워드는 내부 연결용으로만 사용하고
    사용자에게 감정 라벨로 노출하지 않는다 (브랜드 원칙 11.2).
    """
    __tablename__ = "memory_keywords"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    record_id: Mapped[str] = mapped_column(ForeignKey("daily_film_records.id"), index=True)
    keyword_text: Mapped[str] = mapped_column(String(100), index=True)
    # person | place | goal | worry | event | emotion_expression | routine | season | relationship
    keyword_type: Mapped[str] = mapped_column(String(50), default="event")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    record: Mapped["DailyFilmRecord"] = relationship(back_populates="keywords")


class Moment(Base):
    """순간 기록 (3차: 순간 기록형 확장).

    하루 중 스치는 순간을 짧게 남겨두면, 밤 회고 시작 시
    AI 질문 생성의 참고 컨텍스트로 쓰인다.
    """
    __tablename__ = "moments"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    date: Mapped[date] = mapped_column(Date, index=True)
    text: Mapped[str] = mapped_column(EncryptedText)
    photo_id: Mapped[str | None] = mapped_column(ForeignKey("photos.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class RecordEmbedding(Base):
    """기록 임베딩 (3차: 고도화된 기억 연결).

    MVP: 벡터를 JSON으로 저장하고 파이썬에서 코사인 유사도 계산.
    [운영 전환] PostgreSQL + pgvector로 옮기면 DB에서 바로 유사도 검색 가능.
    """
    __tablename__ = "record_embeddings"

    record_id: Mapped[str] = mapped_column(ForeignKey("daily_film_records.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    vector_json: Mapped[str] = mapped_column(Text)          # list[float] 직렬화
    model: Mapped[str] = mapped_column(String(100))          # 어떤 임베딩 모델로 만들었는지
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class Report(Base):
    """월간/연간 회고 리포트 캐시 (3차).

    LLM 호출 비용이 크므로 생성 결과를 저장해두고 재사용한다.
    """
    __tablename__ = "reports"
    __table_args__ = (UniqueConstraint("user_id", "period_type", "period_key", name="uq_user_period"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    period_type: Mapped[str] = mapped_column(String(10))    # monthly | yearly
    period_key: Mapped[str] = mapped_column(String(10))     # "2026-07" | "2026"
    content_json: Mapped[str] = mapped_column(Text)         # ReportOutput 직렬화
    record_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class UserSetting(Base):
    """사용자별 서비스 설정.

    recall_enabled: 회상 기능 전체 켜기/끄기 (서비스 PRD 17장 — 기억 통제권은 사용자에게).
    reminder_time: [FUTURE] 저녁 회고 리마인더 시각(HH:MM). 저장만 하며,
                   실제 발송은 푸시 인프라 도입 시 services/notifications.py 참고.
    """
    __tablename__ = "user_settings"

    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    recall_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    reminder_time: Mapped[str | None] = mapped_column(String(5), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_now, onupdate=_now)


class ShareLink(Base):
    """필름 카드 공유 링크 (서비스 PRD 14장 확장: 결과물 공유).

    공유 응답에는 대화 원문·기억 포인트·위치를 절대 포함하지 않는다 (개발 PRD 8장).
    """
    __tablename__ = "share_links"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    token: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    record_id: Mapped[str] = mapped_column(ForeignKey("daily_film_records.id"), index=True)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class MemoryLink(Base):
    """과거↔현재 기록 연결 (PRD 9.5)."""
    __tablename__ = "memory_links"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    current_record_id: Mapped[str] = mapped_column(ForeignKey("daily_film_records.id"), index=True)
    past_record_id: Mapped[str] = mapped_column(ForeignKey("daily_film_records.id"))
    link_reason: Mapped[str] = mapped_column(String(200))
    link_sentence: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
