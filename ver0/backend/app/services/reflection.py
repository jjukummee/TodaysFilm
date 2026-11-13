"""회고 오케스트레이션: 질문 생성 → 답변 → 필름 생성 → 과거 기록 연결.

라우터는 이 서비스만 호출하고, AI 프로바이더 세부사항은 모른다.
"""
import json
import re

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..ai.base import AIUnavailableError, QAItem
from ..ai.factory import get_ai_provider
from ..ai.prompts import FALLBACK_QUESTIONS, QUESTION_STAGES
from ..config import get_settings
from ..models import (
    AIQuestion, DailyFilmRecord, MemoryKeyword, MemoryLink, Moment, Photo, UserAnswer, UserSetting,
)
from . import embeddings, images


def _history(record: DailyFilmRecord) -> list[QAItem]:
    """기록의 질문/답변을 QAItem 리스트로 변환."""
    items = []
    for q in record.questions:
        if q.answer is not None:
            items.append(QAItem(question=q.question_text, answer=q.answer.answer_text, skipped=q.answer.skipped))
    return items


def next_question(db: Session, record: DailyFilmRecord, regenerate: bool) -> AIQuestion:
    """다음 질문 생성. regenerate=True 면 마지막 미답변 질문을 교체."""
    settings = get_settings()
    provider = get_ai_provider()

    unanswered = [q for q in record.questions if q.answer is None]

    if regenerate:
        if not unanswered:
            raise ValueError("다시 생성할 미답변 질문이 없어요.")
        target = unanswered[-1]
        # 비용 가드레일: 질문당 재생성 횟수 제한
        if target.regeneration_count >= settings.max_regenerations_per_question:
            raise ValueError("질문 다시 받기 한도를 초과했어요.")
        order, avoid, regen_count = target.question_order, target.question_text, target.regeneration_count + 1
        db.delete(target)
        db.flush()
    else:
        if unanswered:
            return unanswered[-1]  # 아직 답 안 한 질문이 있으면 그걸 반환
        if len(record.questions) >= settings.max_questions:
            raise ValueError("질문이 모두 끝났어요. 필름을 생성해 주세요.")
        order, avoid, regen_count = len(record.questions) + 1, None, 0

    # 마지막(closing) 질문 차례에 과거 기록 연결 시도 (개발 PRD 6.4 — 회고당 최대 1회).
    # "질문 다시 받기"는 사용자가 반응하지 않은 것이므로 recall 을 다시 밀지 않는다.
    recall_past: DailyFilmRecord | None = None
    if order == settings.max_questions and not regenerate:
        recall_past = _find_recall_candidate(db, record)

    # Vision 별도 단계 (개발 PRD 6.1): 첫 질문 전에 대표 사진 맥락을 추출·저장하고,
    # 질문 생성에는 원본 이미지 대신 맥락 텍스트만 전달한다 (비용·재사용).
    stage = QUESTION_STAGES.get(order, QUESTION_STAGES[3])
    question_type = "recall" if recall_past else stage["type"]
    try:
        text = provider.generate_question(
            images=[],
            history=_history(record),
            question_order=order,
            question_type=question_type,
            avoid_question=avoid,
            context=(
                _recall_context(recall_past) if recall_past
                else _build_context(db, record) if order == 1 else None  # 첫 질문에만 참고 정보
            ),
        )
    except AIUnavailableError:
        # 개발 PRD 7장: 질문 생성 실패 시 질문 유형 풀에서 기본 질문 폴백 (recall 은 포기)
        recall_past, question_type = None, stage["type"]
        pool = FALLBACK_QUESTIONS.get(order, FALLBACK_QUESTIONS[3])
        text = next((q for q in pool if q != avoid), pool[0])

    question = AIQuestion(
        record_id=record.id,
        question_order=order,
        question_text=text,
        question_type=question_type,
        recall_record_id=recall_past.id if recall_past else None,
        regeneration_count=regen_count,
    )
    db.add(question)
    db.commit()
    db.refresh(question)
    return question


def _recall_enabled(db: Session, user_id: str) -> bool:
    """회상 기능 사용자 설정 (서비스 PRD 17장). 설정 행이 없으면 기본 켜짐."""
    setting = db.get(UserSetting, user_id)
    return setting.recall_enabled if setting else True


def _find_recall_candidate(db: Session, record: DailyFilmRecord) -> DailyFilmRecord | None:
    """recall 질문으로 대체할 과거 기록 탐색.

    정밀도 우선 (개발 PRD 6.4): 임계값 미달·설정 꺼짐·답변 없음이면 None.
    임베딩 실패도 None — 회고는 계속된다.
    """
    settings = get_settings()
    if not _recall_enabled(db, record.user_id):
        return None
    answers = [
        q.answer.answer_text for q in record.questions
        if q.answer and not q.answer.skipped and q.answer.answer_text.strip()
    ]
    if not answers:
        return None
    result = embeddings.find_similar_by_text(
        db, record, " / ".join(answers), min_days_apart=settings.recall_min_days_apart
    )
    if result and result[1] >= settings.recall_threshold:
        return result[0]
    return None


def _recall_context(past: DailyFilmRecord) -> str:
    """recall 질문 생성용 과거 기록 요약 (결과물이 아닌 질문 단서로만 쓰인다)."""
    return (
        f"과거 기록 ({past.date.isoformat()}): "
        f"{past.film_title or ''} / {past.representative_sentence or ''}"
    )


def _ensure_photo_context(db: Session, photo: Photo) -> dict | None:
    """대표 사진의 Vision 맥락을 확보한다 (개발 PRD 6.1).

    이미 저장돼 있으면 재사용(비용 절감), 없으면 분석 후 Photo.ai_context 에 저장.
    Vision 실패는 회고를 막지 않는다 (fail-soft — 맥락 없이 질문 생성).
    """
    if photo.ai_context:
        try:
            return json.loads(photo.ai_context)
        except json.JSONDecodeError:
            return None
    try:
        ctx = get_ai_provider().analyze_photo(images.resize_for_ai(photo.file_path))
    except Exception:
        return None
    photo.ai_context = json.dumps(ctx, ensure_ascii=False)
    db.flush()
    return ctx


def _photo_context_text(db: Session, record: DailyFilmRecord) -> str | None:
    """Vision 맥락 → 프롬프트용 한 줄 (사용자에게는 절대 노출하지 않는다)."""
    main = next((p for p in record.photos if p.is_main), record.photos[0] if record.photos else None)
    if main is None:
        return None
    ctx = _ensure_photo_context(db, main)
    if not ctx:
        return None
    parts = []
    if ctx.get("scene"):
        parts.append(f"장소 유형: {ctx['scene']}")
    if ctx.get("objects"):
        parts.append("보이는 것: " + ", ".join(ctx["objects"][:4]))
    if ctx.get("mood_hint"):
        parts.append(f"분위기 힌트: {ctx['mood_hint']}")
    return "대표 사진의 맥락 — " + " / ".join(parts) if parts else None


def _build_context(db: Session, record: DailyFilmRecord) -> str | None:
    """첫 질문 생성용 참고 컨텍스트 (Vision 맥락 + 순간 기록 + 위치/날씨).

    AI가 하루의 단서를 더 갖고 질문하되, 단정하지 않도록 프롬프트에서 통제한다.
    """
    lines = []
    photo_ctx = _photo_context_text(db, record)
    if photo_ctx:
        lines.append(photo_ctx)
    moments = db.scalars(
        select(Moment)
        .where(Moment.user_id == record.user_id, Moment.date == record.date)
        .order_by(Moment.created_at)
    ).all()
    if moments:
        lines.append("오늘 사용자가 남긴 순간 메모:")
        lines.extend(f"- {m.text}" for m in moments[:10])
    if record.location_name:
        lines.append(f"사진을 찍은 장소: {record.location_name}")
    if record.weather_summary:
        lines.append(f"그날의 날씨: {record.weather_summary}")
    return "\n".join(lines) if lines else None


def split_sentences(text: str) -> list[str]:
    """답변 텍스트 → 문장 단위 분리 (quote 후보용)."""
    return [s.strip() for s in re.split(r"[.!?…\n]+", text) if s.strip()]


def _normalize(text: str) -> str:
    return " ".join(text.split())


def quote_is_from_answers(quote: str, answer_texts: list[str]) -> bool:
    """개발 PRD 원칙 #4: quote 는 사용자 답변 원문에 실제로 포함된 문장이어야 한다."""
    q = _normalize(quote)
    return bool(q) and any(q in _normalize(a) for a in answer_texts)


def quote_candidates_from(answer_texts: list[str]) -> list[str]:
    """답변 원문에서 기억 문장 교체 후보 추출 (개발 PRD 6.3 quote_candidates)."""
    seen: dict[str, None] = {}
    for text in answer_texts:
        for sentence in split_sentences(text):
            seen.setdefault(sentence)
    return list(seen)[:5]


def generate_film(db: Session, record: DailyFilmRecord) -> tuple[DailyFilmRecord, MemoryLink | None, list[str]]:
    """필름 결과 생성 + quote 원문 검증 + 키워드 저장 + 과거 기록 연결."""
    provider = get_ai_provider()
    history = _history(record)
    context = _photo_context_text(db, record)

    answered = [h.answer for h in history if not h.skipped and h.answer.strip()]

    film = provider.generate_film(history, context=context)

    # 원칙 #4: quote 가 답변 원문에 없으면 LLM 창작으로 보고 원문 문장으로 대체
    candidates = quote_candidates_from(answered)
    quote = film.representative_sentence.strip()
    if not quote_is_from_answers(quote, answered):
        quote = max(candidates, key=len, default=None)

    record.film_title = film.film_title
    record.ending_narration = film.ending_narration
    record.representative_sentence = quote

    if not answered:
        # 개발 PRD 6.3·7장: 답변 0개 → 사진 맥락 기반 중립 제목만 채우고
        # '이어서 회고하기' 상태(in_progress) 유지. 키워드/연결은 재료가 없으므로 생략.
        db.commit()
        db.refresh(record)
        return record, None, []

    record.status = "completed"

    # 기존 키워드 갱신 (재생성 대비)
    for kw in list(record.keywords):
        db.delete(kw)
    for kw_text in film.keywords:
        db.add(MemoryKeyword(user_id=record.user_id, record_id=record.id, keyword_text=kw_text))
    db.flush()
    db.expire(record, ["keywords"])  # 방금 교체한 키워드를 관계에 반영 (기억 연결에서 사용)

    # 3차: 기억 연결용 임베딩 저장 (실패해도 회고는 계속)
    embeddings.upsert_embedding(db, record)

    link = _find_memory_link(db, record)
    db.commit()
    db.refresh(record)
    return record, link, candidates


def _find_memory_link(db: Session, record: DailyFilmRecord) -> MemoryLink | None:
    """과거 기록 연결 (PRD 7.6 — 3차 '고도화된 기억 연결' 적용).

    1순위: 임베딩 유사도 — "취업 걱정"↔"첫 출근" 같은 의미적 연결을 잡는다.
    2순위(폴백): 키워드 겹침 — 임베딩이 없거나 유사도가 낮을 때.
    최종적으로 LLM이 연결 문장을 만들 가치가 있는지 판단한다 (없으면 None).
    """
    settings = get_settings()
    if not _recall_enabled(db, record.user_id):
        return None

    # 대화 중 recall 질문으로 이미 연결을 제시한 경우 (개발 PRD 6.4 — 회고당 최대 1회):
    # 사용자가 답했을 때만 결과물에 포함하고, 새 연결은 더 찾지 않는다 (서비스 PRD 9 예외 흐름).
    recall_q = next(
        (q for q in record.questions if q.question_type == "recall" and q.recall_record_id), None
    )
    if recall_q:
        reacted = recall_q.answer and not recall_q.answer.skipped and recall_q.answer.answer_text.strip()
        past = db.get(DailyFilmRecord, recall_q.recall_record_id) if reacted else None
        if past is None:
            return None
        link = MemoryLink(
            user_id=record.user_id,
            current_record_id=record.id,
            past_record_id=past.id,
            link_reason="recall_question",
            link_sentence=_link_sentence(past, record)
            or f"{past.date.isoformat()}의 기록과 이어지는 하루였어요.",
        )
        db.add(link)
        return link

    best, reason = None, ""

    # ── 1순위: 임베딩 유사도 (3차) ──
    result = embeddings.find_similar_record(db, record, min_days_apart=settings.recall_min_days_apart)
    if result and result[1] >= settings.recall_threshold:
        best, reason = result[0], f"embedding:{result[1]:.2f}"

    # ── 2순위 폴백: 키워드 겹침 ──
    if best is None:
        my_keywords = {k.keyword_text for k in record.keywords}
        if my_keywords:
            past_records = db.scalars(
                select(DailyFilmRecord)
                .where(
                    DailyFilmRecord.user_id == record.user_id,
                    DailyFilmRecord.id != record.id,
                    DailyFilmRecord.status == "completed",
                    DailyFilmRecord.recall_blocked.is_(False),  # "다시 꺼내지 않기" 제외
                )
                .order_by(DailyFilmRecord.date.desc())
                .limit(100)
            ).all()
            best_overlap: set = set()
            for past in past_records:
                if (record.date - past.date).days < settings.recall_min_days_apart:
                    continue
                overlap = my_keywords & {k.keyword_text for k in past.keywords}
                if len(overlap) > len(best_overlap):
                    best, best_overlap = past, overlap
            if best is not None:
                reason = "keyword:" + ",".join(sorted(best_overlap))

    if best is None:
        return None

    sentence = _link_sentence(best, record)
    if not sentence:
        return None  # PRD 10.3: 명확한 연결점이 있을 때만

    link = MemoryLink(
        user_id=record.user_id,
        current_record_id=record.id,
        past_record_id=best.id,
        link_reason=reason,
        link_sentence=sentence,
    )
    db.add(link)
    return link


def _link_sentence(past: DailyFilmRecord, current: DailyFilmRecord) -> str | None:
    """과거↔현재 연결 문장. LLM 장애·거절 시 None (연결은 부가 기능 — 필름 생성을 막지 않음)."""
    try:
        return get_ai_provider().generate_link_sentence(
            past_date=past.date.isoformat(),
            past_summary=f"{past.film_title or ''} / {past.representative_sentence or ''}",
            current_summary=f"{current.film_title or ''} / {current.representative_sentence or ''}",
        )
    except Exception:
        return None
