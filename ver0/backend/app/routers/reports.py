"""월간/연간 회고 리포트 (3차, PRD 16.3 '이달의 상영관')."""
import json

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import Report, User
from ..schemas import ReportOut
from ..services import reports as report_service

router = APIRouter(prefix="/reports", tags=["reports"])


def _to_out(report: Report) -> ReportOut:
    content = json.loads(report.content_json)
    return ReportOut(
        period_type=report.period_type,
        period_key=report.period_key,
        report_title=content.get("report_title", ""),
        narration=content.get("narration", ""),
        highlights=content.get("highlights", []),
        keywords=content.get("keywords", []),
        record_count=report.record_count,
        created_at=report.created_at,
    )


@router.get("/monthly", response_model=ReportOut)
def monthly_report(
    year: int = Query(ge=2000, le=2100),
    month: int = Query(ge=1, le=12),
    regenerate: bool = Query(default=False, description="true면 캐시 무시하고 재생성"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        report = report_service.get_or_create_report(db, user, "monthly", year, month, regenerate)
    except ValueError as e:
        raise HTTPException(404, str(e))
    return _to_out(report)


@router.get("/yearly", response_model=ReportOut)
def yearly_report(
    year: int = Query(ge=2000, le=2100),
    regenerate: bool = Query(default=False),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        report = report_service.get_or_create_report(db, user, "yearly", year, None, regenerate)
    except ValueError as e:
        raise HTTPException(404, str(e))
    return _to_out(report)
