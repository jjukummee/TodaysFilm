"""회고 기록: 생성 → 질문 → 답변 → 필름 생성 → 조회/수정/삭제."""
from datetime import date as date_type

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..database import get_db
from ..deps import get_current_user
from ..models import (
    AIQuestion, DailyFilmRecord, MemoryLink, Photo, RecordEmbedding, ShareLink, User, UserAnswer,
)
from ..rate_limit import llm_rate_limit
from ..schemas import (
    AnswerOut, AnswerRequest, AnswerUpdateRequest, FilmResult, MemoryLinkOut, QuestionOut,
    QuestionRequest, RecallPreview, RecordCreateRequest, RecordDetail, RecordUpdateRequest,
)
from ..services import reflection, safety
from ..services.weather import get_weather_summary
from ..timeutil import today_kst
from .photos import photo_url as _photo_url_impl

router = APIRouter(prefix="/records", tags=["records"])


def _get_owned_record(record_id: str, user: User, db: Session) -> DailyFilmRecord:
    record = db.get(DailyFilmRecord, record_id)
    if record is None or record.user_id != user.id:
        raise HTTPException(404, "기록을 찾을 수 없어요.")
    return record


def _photo_url(p: Photo) -> str:
    # 인증된 사진 서빙 URL (routers/photos.py)
    return _photo_url_impl(p)


def _link_out(db: Session, link: MemoryLink) -> MemoryLinkOut:
    past = db.get(DailyFilmRecord, link.past_record_id)
    return MemoryLinkOut(
        past_record_id=link.past_record_id,
        past_date=past.date if past else date_type.min,
        link_reason=link.link_reason,
        link_sentence=link.link_sentence,
    )


def _question_out(db: Session, question: AIQuestion) -> QuestionOut:
    """recall형 질문이면 과거 기록 미리보기를 함께 내려준다 (개발 PRD 6.4)."""
    out = QuestionOut.model_validate(question)
    if question.recall_record_id:
        past = db.get(DailyFilmRecord, question.recall_record_id)
        if past:
            out.recall = RecallPreview(
                past_record_id=past.id,
                past_date=past.date,
                film_title=past.film_title,
                representative_sentence=past.representative_sentence,
            )
    return out


def _detail(db: Session, record: DailyFilmRecord) -> RecordDetail:
    links = db.scalars(select(MemoryLink).where(MemoryLink.current_record_id == record.id)).all()
    return RecordDetail(
        id=record.id,
        date=record.date,
        status=record.status,
        recall_blocked=record.recall_blocked,
        film_title=record.film_title,
        ending_narration=record.ending_narration,
        representative_sentence=record.representative_sentence,
        keywords=[k.keyword_text for k in record.keywords],
        photos=[
            {"id": p.id, "url": _photo_url(p), "is_main": p.is_main} for p in record.photos
        ],
        questions=[_question_out(db, q) for q in record.questions],
        answers=[q.answer for q in record.questions if q.answer is not None],
        memory_links=[_link_out(db, l) for l in links],
        location_name=record.location_name,
        weather_summary=record.weather_summary,
        created_at=record.created_at,
    )


# ─── 1. 기록 생성 (사진 선택 완료 시점) ─────────────────
@router.post("", response_model=RecordDetail, status_code=201)
def create_record(body: RecordCreateRequest, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    record_date = body.date or today_kst()

    # 하루 = 필름 1개 원칙
    dup = db.scalar(
        select(DailyFilmRecord).where(DailyFilmRecord.user_id == user.id, DailyFilmRecord.date == record_date)
    )
    if dup:
        raise HTTPException(409, "이 날짜에는 이미 필름이 있어요. 기존 기록을 수정해 주세요.")

    # 개발 PRD 5장 (MVP 1~3장) — 상한은 config.max_photos_per_film 로 조정
    max_photos = get_settings().max_photos_per_film
    if len(body.photo_ids) > max_photos:
        raise HTTPException(400, f"사진은 최대 {max_photos}장까지 선택할 수 있어요.")

    if body.main_photo_id not in body.photo_ids:
        raise HTTPException(400, "대표 사진은 선택한 사진 중에서 지정해야 해요.")

    photos = db.scalars(select(Photo).where(Photo.id.in_(body.photo_ids), Photo.user_id == user.id)).all()
    if len(photos) != len(set(body.photo_ids)):
        raise HTTPException(400, "존재하지 않는 사진이 포함되어 있어요.")

    record = DailyFilmRecord(user_id=user.id, date=record_date)

    # ─── 3차: 위치/날씨 기반 회고 보조 ───
    if body.location:
        record.location_name = body.location.name
        record.latitude = body.location.latitude
        record.longitude = body.location.longitude
        if body.location.latitude is not None and body.location.longitude is not None:
            record.weather_summary = get_weather_summary(body.location.latitude, body.location.longitude)

    db.add(record)
    db.flush()

    for p in photos:
        p.record_id = record.id
        p.is_main = p.id == body.main_photo_id

    db.commit()
    db.refresh(record)
    return _detail(db, record)


# ─── 2. AI 질문 받기 / 다시 받기 ───────────────────────
@router.post("/{record_id}/questions", response_model=QuestionOut)
def get_question(
    record_id: str,
    body: QuestionRequest,
    user: User = Depends(llm_rate_limit),  # LLM 비용 가드레일
    db: Session = Depends(get_db),
):
    record = _get_owned_record(record_id, user, db)
    try:
        question = reflection.next_question(db, record, regenerate=body.regenerate)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return _question_out(db, question)


# ─── 3. 답변 저장 (건너뛰기 포함) ──────────────────────
@router.post("/{record_id}/answers", response_model=AnswerOut, status_code=201)
def submit_answer(
    record_id: str,
    body: AnswerRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    record = _get_owned_record(record_id, user, db)
    question = next((q for q in record.questions if q.id == body.question_id), None)
    if question is None:
        raise HTTPException(404, "질문을 찾을 수 없어요.")
    if question.answer is not None:
        raise HTTPException(409, "이미 답변한 질문이에요. 수정은 PATCH /answers/{id} 를 사용하세요.")
    if not body.skipped and not body.answer_text.strip():
        raise HTTPException(400, "답변을 입력하거나 건너뛰기를 선택해 주세요.")

    answer = UserAnswer(
        question_id=question.id,
        record_id=record.id,
        answer_text="" if body.skipped else body.answer_text.strip(),
        skipped=body.skipped,
    )
    db.add(answer)
    db.commit()
    db.refresh(answer)

    # 위기 표현 안내 (서비스 PRD 17장) — 응답에만 싣고 저장하지 않는다
    out = AnswerOut.model_validate(answer)
    out.safety_notice = safety.crisis_notice(answer.answer_text)
    return out


# ─── 3-1. 답변 수정 ───────────────────────────────────
@router.patch("/answers/{answer_id}", response_model=AnswerOut)
def update_answer(
    answer_id: str,
    body: AnswerUpdateRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    answer = db.get(UserAnswer, answer_id)
    if answer is None or answer.record.user_id != user.id:
        raise HTTPException(404, "답변을 찾을 수 없어요.")
    answer.answer_text = body.answer_text.strip()
    answer.skipped = False
    db.commit()
    db.refresh(answer)

    out = AnswerOut.model_validate(answer)
    out.safety_notice = safety.crisis_notice(answer.answer_text)
    return out


# ─── 4. 필름 생성 ─────────────────────────────────────
@router.post("/{record_id}/film", response_model=FilmResult)
def generate_film(record_id: str, user: User = Depends(llm_rate_limit), db: Session = Depends(get_db)):
    record = _get_owned_record(record_id, user, db)
    try:
        record, link, candidates = reflection.generate_film(db, record)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return FilmResult(
        film_title=record.film_title,
        ending_narration=record.ending_narration,
        representative_sentence=record.representative_sentence,
        keywords=[k.keyword_text for k in record.keywords],
        quote_candidates=candidates,
        memory_link=_link_out(db, link) if link else None,
    )


# ─── 5. 조회 / 수정 / 삭제 ─────────────────────────────
@router.get("/{record_id}", response_model=RecordDetail)
def get_record(record_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return _detail(db, _get_owned_record(record_id, user, db))


@router.patch("/{record_id}", response_model=RecordDetail)
def update_record(
    record_id: str,
    body: RecordUpdateRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    record = _get_owned_record(record_id, user, db)

    # 서비스 PRD 11장: 제목/한 줄 회고는 자유 수정, 기억 문장은 답변 원문 문장으로만 교체 가능
    if body.representative_sentence is not None:
        answers = [q.answer.answer_text for q in record.questions if q.answer and not q.answer.skipped]
        if not reflection.quote_is_from_answers(body.representative_sentence, answers):
            raise HTTPException(400, "기억 문장은 대화 속 내 답변 문장에서만 고를 수 있어요.")

    for field in ("film_title", "ending_narration", "representative_sentence"):
        value = getattr(body, field)
        if value is not None:
            setattr(record, field, value.strip())

    if body.recall_blocked is not None:  # "다시 꺼내지 않기" (서비스 PRD 17장)
        record.recall_blocked = body.recall_blocked

    db.commit()
    db.refresh(record)
    return _detail(db, record)


@router.delete("/{record_id}", status_code=204)
def delete_record(record_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    record = _get_owned_record(record_id, user, db)
    for link in db.scalars(
        select(MemoryLink).where(
            (MemoryLink.current_record_id == record.id) | (MemoryLink.past_record_id == record.id)
        )
    ):
        db.delete(link)
    for share in db.scalars(select(ShareLink).where(ShareLink.record_id == record.id)):
        db.delete(share)  # 기록이 사라지면 공유 링크도 즉시 무효
    embedding = db.get(RecordEmbedding, record.id)
    if embedding:
        db.delete(embedding)
    db.delete(record)  # 질문/답변/키워드/사진 메타데이터는 cascade 삭제
    db.commit()
