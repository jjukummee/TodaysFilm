"""아카이브: 월간 캘린더 + 키워드 검색 (PRD 7.5, 8.7)."""
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import DailyFilmRecord, MemoryKeyword, User
from ..schemas import ArchiveDay, ArchiveMonth
from ..timeutil import today_kst
from .records import _photo_url

router = APIRouter(prefix="/archive", tags=["archive"])


def _day(record: DailyFilmRecord) -> ArchiveDay:
    main = next((p for p in record.photos if p.is_main), record.photos[0] if record.photos else None)
    return ArchiveDay(
        date=record.date,
        record_id=record.id,
        film_title=record.film_title,
        representative_sentence=record.representative_sentence,
        main_photo_url=_photo_url(main) if main else None,
    )


@router.get("/calendar", response_model=ArchiveMonth)
def month_calendar(
    year: int = Query(ge=2000, le=2100),
    month: int = Query(ge=1, le=12),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """월간 캘린더: 기록 있는 날짜 + 미리보기."""
    start = date(year, month, 1)
    end = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)

    records = db.scalars(
        select(DailyFilmRecord)
        .where(
            DailyFilmRecord.user_id == user.id,
            DailyFilmRecord.date >= start,
            DailyFilmRecord.date < end,
        )
        .order_by(DailyFilmRecord.date)
    ).all()

    return ArchiveMonth(year=year, month=month, record_count=len(records), days=[_day(r) for r in records])


@router.get("/search", response_model=list[ArchiveDay])
def search(
    keyword: str = Query(min_length=1, max_length=50),
    limit: int = Query(default=50, ge=1, le=200),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """키워드로 과거 필름 검색 (최신순, limit 페이징)."""
    record_ids = db.scalars(
        select(MemoryKeyword.record_id).where(
            MemoryKeyword.user_id == user.id,
            MemoryKeyword.keyword_text.contains(keyword),
        )
    ).all()

    records = db.scalars(
        select(DailyFilmRecord)
        .where(DailyFilmRecord.id.in_(set(record_ids)))
        .order_by(DailyFilmRecord.date.desc())
        .limit(limit)
    ).all()
    return [_day(r) for r in records]


@router.get("/on-this-day", response_model=list[ArchiveDay])
def on_this_day(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """홈 화면 '과거의 오늘' 카드용 (PRD 8.2)."""
    today = today_kst()
    records = db.scalars(
        select(DailyFilmRecord).where(
            DailyFilmRecord.user_id == user.id,
            DailyFilmRecord.status == "completed",
        )
    ).all()
    matches = [r for r in records if r.date.month == today.month and r.date.day == today.day and r.date != today]
    return [_day(r) for r in matches]
