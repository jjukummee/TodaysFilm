"""회원가입 / 로그인 / 내 정보 / 설정 / 데이터 내보내기."""
from datetime import timedelta
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import (
    DailyFilmRecord, MemoryLink, Moment, Photo, RecordEmbedding, Report, ShareLink, User,
    UserSetting,
)
from ..rate_limit import auth_rate_limit
from ..schemas import (
    LoginRequest, SignupRequest, TokenResponse, UserOut, UserSettingsOut, UserSettingsUpdate,
    UserStats, UserUpdateRequest,
)
from ..security import create_access_token, hash_password, verify_password
from ..timeutil import today_kst
from .records import _detail

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", response_model=TokenResponse, status_code=201,
             dependencies=[Depends(auth_rate_limit)])  # 브루트포스 방지
def signup(body: SignupRequest, db: Session = Depends(get_db)):
    exists = db.scalar(select(User).where(User.email == body.email))
    if exists:
        raise HTTPException(status.HTTP_409_CONFLICT, "이미 가입된 이메일이에요.")
    user = User(email=body.email, password_hash=hash_password(body.password), nickname=body.nickname)
    db.add(user)
    db.commit()
    return TokenResponse(access_token=create_access_token(user.id))


@router.post("/login", response_model=TokenResponse,
             dependencies=[Depends(auth_rate_limit)])  # 브루트포스 방지
def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == body.email))
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "이메일 또는 비밀번호가 맞지 않아요.")
    return TokenResponse(access_token=create_access_token(user.id))


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return user


@router.patch("/me", response_model=UserOut)
def update_me(body: UserUpdateRequest, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    user.nickname = body.nickname.strip()
    db.commit()
    db.refresh(user)
    return user


# ─── 사용자 설정 (회상 켜기/끄기 등) ───────────────────
def _get_or_create_settings(db: Session, user_id: str) -> UserSetting:
    setting = db.get(UserSetting, user_id)
    if setting is None:
        setting = UserSetting(user_id=user_id)
        db.add(setting)
        db.commit()
        db.refresh(setting)
    return setting


@router.get("/me/settings", response_model=UserSettingsOut)
def my_settings(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return _get_or_create_settings(db, user.id)


@router.patch("/me/settings", response_model=UserSettingsOut)
def update_settings(
    body: UserSettingsUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    setting = _get_or_create_settings(db, user.id)
    if body.recall_enabled is not None:
        setting.recall_enabled = body.recall_enabled
    if "reminder_time" in body.model_fields_set:  # null 로 해제 가능해야 해서 명시 여부로 판단
        setting.reminder_time = body.reminder_time
    db.commit()
    db.refresh(setting)
    return setting


@router.get("/me/stats", response_model=UserStats)
def my_stats(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """마이페이지 통계: 완성 필름 수 / 연속 기록 일수 / 받은 질문 수."""
    records = db.scalars(
        select(DailyFilmRecord).where(DailyFilmRecord.user_id == user.id)
    ).all()

    total_films = sum(1 for r in records if r.status == "completed")
    questions_received = sum(len(r.questions) for r in records)

    # 연속 기록: 오늘(기록 없으면 어제)부터 거꾸로 이어진 날짜 수
    dates = {r.date for r in records}
    today = today_kst()
    day = today if today in dates else today - timedelta(days=1)
    streak_days = 0
    while day in dates:
        streak_days += 1
        day -= timedelta(days=1)

    return UserStats(
        total_films=total_films,
        streak_days=streak_days,
        questions_received=questions_received,
    )


@router.get("/me/export")
def export_my_data(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """내 데이터 전체 내보내기 (개인정보 이동권 — 서비스 PRD 17장 보호 수준의 일부).

    기록·대화·순간 기록을 JSON 으로 반환한다. 암호화 컬럼은 복호화된 평문으로
    나가므로(본인 요청) 응답을 로그에 남기지 않는다.
    """
    records = db.scalars(
        select(DailyFilmRecord)
        .where(DailyFilmRecord.user_id == user.id)
        .order_by(DailyFilmRecord.date)
    ).all()
    moments = db.scalars(
        select(Moment).where(Moment.user_id == user.id).order_by(Moment.date, Moment.created_at)
    ).all()

    return {
        "user": {"email": user.email, "nickname": user.nickname, "created_at": user.created_at},
        "records": [_detail(db, r).model_dump(mode="json") for r in records],
        "moments": [
            {"date": m.date.isoformat(), "text": m.text, "created_at": m.created_at.isoformat()}
            for m in moments
        ],
    }


@router.delete("/me", status_code=204)
def delete_account(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """계정 삭제 (개인정보보호법 필수).

    기록·사진 파일·순간 기록·임베딩·리포트·공유 링크·설정까지 모두 삭제한다.
    """
    # 사진 실파일 삭제
    for photo in db.scalars(select(Photo).where(Photo.user_id == user.id)):
        try:
            Path(photo.file_path).unlink(missing_ok=True)
        except OSError:
            pass  # 파일 삭제 실패가 계정 삭제를 막으면 안 됨

    for model in (ShareLink, MemoryLink, RecordEmbedding, Report, Moment, Photo, DailyFilmRecord):
        for row in db.scalars(select(model).where(model.user_id == user.id)):
            db.delete(row)
    setting = db.get(UserSetting, user.id)
    if setting:
        db.delete(setting)
    db.delete(user)
    db.commit()
