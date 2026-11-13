"""순간 기록 (3차: 순간 기록형 확장).

하루 중 스치는 순간을 짧게 남기면, 밤 회고 시작 시
AI 첫 질문의 참고 컨텍스트로 자동 활용된다 (services/reflection.py).
"""
from datetime import date as date_cls

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import Moment, Photo, User
from ..schemas import MomentCreateRequest, MomentOut
from ..timeutil import today_kst

router = APIRouter(prefix="/moments", tags=["moments"])

MAX_MOMENTS_PER_DAY = 20  # 가드레일


@router.post("", response_model=MomentOut, status_code=201)
def create_moment(body: MomentCreateRequest, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    moment_date = body.date or today_kst()

    count = len(db.scalars(
        select(Moment).where(Moment.user_id == user.id, Moment.date == moment_date)
    ).all())
    if count >= MAX_MOMENTS_PER_DAY:
        raise HTTPException(400, f"순간 기록은 하루 {MAX_MOMENTS_PER_DAY}개까지 남길 수 있어요.")

    if body.photo_id:
        photo = db.get(Photo, body.photo_id)
        if photo is None or photo.user_id != user.id:
            raise HTTPException(400, "존재하지 않는 사진이에요.")

    moment = Moment(user_id=user.id, date=moment_date, text=body.text.strip(), photo_id=body.photo_id)
    db.add(moment)
    db.commit()
    db.refresh(moment)
    return moment


@router.get("", response_model=list[MomentOut])
def list_moments(
    date: str | None = Query(default=None, description="YYYY-MM-DD, 미지정 시 오늘"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    target = date_cls.fromisoformat(date) if date else today_kst()
    return db.scalars(
        select(Moment)
        .where(Moment.user_id == user.id, Moment.date == target)
        .order_by(Moment.created_at)
    ).all()


@router.delete("/{moment_id}", status_code=204)
def delete_moment(moment_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    moment = db.get(Moment, moment_id)
    if moment is None or moment.user_id != user.id:
        raise HTTPException(404, "순간 기록을 찾을 수 없어요.")
    db.delete(moment)
    db.commit()
