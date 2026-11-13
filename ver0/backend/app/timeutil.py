"""KST 시간 헬퍼.

'오늘'은 서비스 전역에서 Asia/Seoul 기준이다 (자정 넘긴 새벽 회고는
클라이언트가 어제 날짜를 명시적으로 보내는 방식으로 처리).
"""
from datetime import date, datetime
from zoneinfo import ZoneInfo

KST = ZoneInfo("Asia/Seoul")


def today_kst() -> date:
    return datetime.now(KST).date()
