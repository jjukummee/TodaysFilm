"""[FUTURE — 현재 PRD 범위 밖, 확장 대비 선구현]
저녁 회고 리마인더 발송 (서비스 PRD 5.2: "자기 전 폰을 보는 저녁 루틴" 진입점).

사용자가 /auth/me/settings 로 저장한 reminder_time(HH:MM, KST)에 맞춰
"오늘 하루, 돌아볼까요?" 푸시를 보내는 모듈. 현재는 어디에도 연결되어 있지 않다.

도입 절차:
  1. FCM/APNs 디바이스 토큰 등록 API 추가 (User 에 device_token 컬럼)
  2. _send_push() 를 실제 발송 SDK 로 교체
  3. 스케줄러(cron, APScheduler 등)에서 매 분 send_evening_reminders() 호출
  4. 이미 오늘 기록한 사용자는 제외하는 로직은 아래에 이미 반영되어 있음
"""
import logging

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import DailyFilmRecord, UserSetting
from ..timeutil import KST, today_kst

logger = logging.getLogger("todaysfilm")

REMINDER_MESSAGE = "오늘 하루, 돌아볼까요? 사진 한 장이면 충분해요."


def _send_push(user_id: str, message: str) -> None:
    """[스텁] 실제 푸시 발송 지점. FCM/APNs 도입 시 이 함수만 교체."""
    logger.info("reminder (미발송 스텁): user=%s message=%s", user_id, message)


def send_evening_reminders(db: Session, now_hhmm: str | None = None) -> int:
    """reminder_time 이 현재 시각(KST)과 일치하는 사용자에게 리마인더 발송.

    오늘 이미 기록을 남긴 사용자는 건너뛴다. 발송(시도) 수를 반환한다.
    """
    from datetime import datetime

    current = now_hhmm or datetime.now(KST).strftime("%H:%M")
    today = today_kst()

    targets = db.scalars(
        select(UserSetting).where(UserSetting.reminder_time == current)
    ).all()

    sent = 0
    for setting in targets:
        has_record_today = db.scalar(
            select(DailyFilmRecord.id).where(
                DailyFilmRecord.user_id == setting.user_id,
                DailyFilmRecord.date == today,
            )
        )
        if has_record_today:
            continue
        _send_push(setting.user_id, REMINDER_MESSAGE)
        sent += 1
    return sent
