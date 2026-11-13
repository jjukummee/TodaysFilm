"""월간/연간 회고 리포트 (3차, PRD 16.3).

LLM 호출 비용이 크므로 결과를 reports 테이블에 캐시한다.
같은 기간을 다시 요청하면 저장본을 반환하고, regenerate=True 일 때만 재생성.
"""
import json
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..ai.factory import get_ai_provider
from ..models import DailyFilmRecord, Report, User


def _load_entries(db: Session, user: User, start: date, end: date, yearly: bool) -> list[dict]:
    records = db.scalars(
        select(DailyFilmRecord)
        .where(
            DailyFilmRecord.user_id == user.id,
            DailyFilmRecord.status == "completed",
            DailyFilmRecord.date >= start,
            DailyFilmRecord.date < end,
        )
        .order_by(DailyFilmRecord.date)
    ).all()

    entries = []
    for r in records:
        entry = {
            "date": r.date.isoformat(),
            "film_title": r.film_title,
            "keywords": [k.keyword_text for k in r.keywords],
        }
        # 연간 리포트는 기록이 많아 토큰이 커지므로 대표 문장은 월간에만 포함
        if not yearly:
            entry["representative_sentence"] = r.representative_sentence
        entries.append(entry)
    return entries


def get_or_create_report(
    db: Session,
    user: User,
    period_type: str,   # "monthly" | "yearly"
    year: int,
    month: int | None = None,
    regenerate: bool = False,
) -> Report:
    yearly = period_type == "yearly"
    period_key = str(year) if yearly else f"{year}-{month:02d}"

    existing = db.scalar(
        select(Report).where(
            Report.user_id == user.id,
            Report.period_type == period_type,
            Report.period_key == period_key,
        )
    )
    if existing and not regenerate:
        return existing

    if yearly:
        start, end = date(year, 1, 1), date(year + 1, 1, 1)
        period_label = f"{year}년"
    else:
        start = date(year, month, 1)
        end = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
        period_label = f"{year}년 {month}월"

    entries = _load_entries(db, user, start, end, yearly)
    if len(entries) < 3:
        raise ValueError("리포트를 만들려면 이 기간에 완성된 필름이 3개 이상 필요해요.")

    provider = get_ai_provider()
    output = provider.generate_report(period_label=period_label, entries=entries)

    content = json.dumps({
        "report_title": output.report_title,
        "narration": output.narration,
        "highlights": output.highlights,
        "keywords": output.keywords,
    }, ensure_ascii=False)

    if existing:
        existing.content_json = content
        existing.record_count = len(entries)
        report = existing
    else:
        report = Report(
            user_id=user.id,
            period_type=period_type,
            period_key=period_key,
            content_json=content,
            record_count=len(entries),
        )
        db.add(report)

    db.commit()
    db.refresh(report)
    return report
