"""임베딩 저장/검색 (3차: 고도화된 기억 연결).

MVP: JSON 벡터 + 파이썬 코사인 유사도. 개인 기록은 많아야 수백~수천 건이라
파이썬 계산으로도 충분히 빠르다.
[운영 전환] PostgreSQL + pgvector로 옮기면 이 파일 내부만 교체하면 됨.
"""
import json
import math

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..ai.factory import get_ai_provider
from ..models import DailyFilmRecord, RecordEmbedding


def _cosine(a: list[float], b: list[float]) -> float:
    if len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def build_record_text(record: DailyFilmRecord) -> str:
    """임베딩할 텍스트: 대표 문장 + 답변들 (사용자의 실제 표현이 핵심)."""
    parts = [record.film_title or "", record.representative_sentence or ""]
    for q in record.questions:
        if q.answer and not q.answer.skipped and q.answer.answer_text.strip():
            parts.append(q.answer.answer_text)
    return " / ".join(p for p in parts if p)


def upsert_embedding(db: Session, record: DailyFilmRecord) -> None:
    """필름 생성/재생성 시 호출. 임베딩 실패는 회고를 막지 않는다."""
    provider = get_ai_provider()
    text = build_record_text(record)
    if not text:
        return
    try:
        vector = provider.embed(text)
    except Exception:
        return  # 임베딩 실패 → 키워드 기반 연결로 폴백되므로 무시

    existing = db.get(RecordEmbedding, record.id)
    if existing:
        existing.vector_json = json.dumps(vector)
        existing.model = type(provider).__name__
    else:
        db.add(RecordEmbedding(
            record_id=record.id,
            user_id=record.user_id,
            vector_json=json.dumps(vector),
            model=type(provider).__name__,
        ))
    db.flush()


def _scan_similar(
    db: Session,
    user_id: str,
    query_vec: list[float],
    exclude_record_id: str,
    current_date,
    min_days_apart: int,
) -> tuple[DailyFilmRecord, float] | None:
    """사용자의 완성된 과거 기록 중 가장 유사한 것. 회상 차단 기록은 제외."""
    rows = db.execute(
        select(RecordEmbedding, DailyFilmRecord)
        .join(DailyFilmRecord, RecordEmbedding.record_id == DailyFilmRecord.id)
        .where(
            RecordEmbedding.user_id == user_id,
            RecordEmbedding.record_id != exclude_record_id,
            DailyFilmRecord.status == "completed",
            DailyFilmRecord.recall_blocked.is_(False),  # 서비스 PRD 17장 "다시 꺼내지 않기"
        )
    ).all()

    best, best_score = None, 0.0
    for emb, past in rows:
        if (current_date - past.date).days < min_days_apart:
            continue
        score = _cosine(query_vec, json.loads(emb.vector_json))
        if score > best_score:
            best, best_score = past, score

    return (best, best_score) if best else None


def find_similar_record(
    db: Session, record: DailyFilmRecord, min_days_apart: int = 7
) -> tuple[DailyFilmRecord, float] | None:
    """의미적으로 가장 비슷한 과거 기록을 찾는다. (기록, 유사도) 또는 None."""
    current = db.get(RecordEmbedding, record.id)
    if current is None:
        return None
    return _scan_similar(
        db, record.user_id, json.loads(current.vector_json),
        exclude_record_id=record.id, current_date=record.date, min_days_apart=min_days_apart,
    )


def find_similar_by_text(
    db: Session, record: DailyFilmRecord, text: str, min_days_apart: int = 7
) -> tuple[DailyFilmRecord, float] | None:
    """진행 중인 회고의 답변 텍스트로 과거 기록을 검색한다 (개발 PRD 6.4 recall 질문용).

    아직 임베딩이 저장되지 않은 기록에서 쓴다. 임베딩 실패는 None (회고를 막지 않음).
    """
    if not text.strip():
        return None
    try:
        query_vec = get_ai_provider().embed(text)
    except Exception:
        return None
    return _scan_similar(
        db, record.user_id, query_vec,
        exclude_record_id=record.id, current_date=record.date, min_days_apart=min_days_apart,
    )
