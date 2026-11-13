"""대화 원문 암호화 저장 (개발 PRD 8장 비기능 요구사항).

회고 대화(AIQuestion.question_text, UserAnswer.answer_text)와 순간기록(Moment.text)은
사용자의 내면 이야기라 DB가 유출되어도 읽을 수 없도록 앱 레벨에서 암호화한다.
MemoryKeyword.keyword_text 는 검색(contains)에 쓰이는 인덱스 컬럼이라 대상에서 제외.

- ENCRYPTION_KEY(Fernet)가 설정되면 쓰기 시 암호화, 읽기 시 복호화.
- 키가 없으면 평문으로 동작 (개발 편의). 운영 모드에서는 키가 강제된다 (config.validate_for_production).
- 평문 → 암호화 전환기에도 기존 평문 행을 읽을 수 있도록, 읽기 시
  Fernet 토큰 형태(gAAAA...)일 때만 복호화를 시도한다.
"""
import logging
from functools import lru_cache

from sqlalchemy import Text, TypeDecorator

from ..config import get_settings

logger = logging.getLogger("todaysfilm")

_FERNET_PREFIX = "gAAAA"  # Fernet 토큰은 항상 이 문자열로 시작한다 (version 0x80 + base64)


@lru_cache
def _get_fernet():
    key = get_settings().encryption_key.strip()
    if not key:
        return None
    from cryptography.fernet import Fernet

    return Fernet(key.encode())


class EncryptedText(TypeDecorator):
    """투명 암호화 TEXT 컬럼. 서비스/라우터 코드는 평문 str 로만 다룬다."""

    impl = Text
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        fernet = _get_fernet()
        if fernet is None:
            return value
        return fernet.encrypt(value.encode()).decode()

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        if not value.startswith(_FERNET_PREFIX):
            return value  # 암호화 도입 전에 저장된 평문
        fernet = _get_fernet()
        if fernet is None:
            logger.error("암호화된 데이터가 있지만 ENCRYPTION_KEY 가 없습니다")
            return value
        try:
            return fernet.decrypt(value.encode()).decode()
        except Exception:
            logger.exception("복호화 실패 — 키가 바뀌었는지 확인하세요")
            return value
