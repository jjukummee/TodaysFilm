"""대화 암호화 저장 검증 (개발 PRD 8장).

test_api.py 는 ENCRYPTION_KEY 없이 평문 경로를 검증하므로,
여기서는 키가 있을 때 ①DB 원값은 암호문 ②ORM 읽기는 평문
③암호화 도입 전 평문 행도 읽힘 을 검증한다.
"""
from datetime import date

import pytest
from cryptography.fernet import Fernet
from sqlalchemy import create_engine, text as sql_text
from sqlalchemy.orm import Session

from app import models
from app.config import get_settings
from app.services import crypto
from app.services.crypto import EncryptedText


def test_encrypted_columns_wired():
    """대상 3개 컬럼에 EncryptedText 가 실제로 적용되어 있는지 (배선 회귀 방지)."""
    for column in (
        models.AIQuestion.__table__.c.question_text,
        models.UserAnswer.__table__.c.answer_text,
        models.Moment.__table__.c.text,
    ):
        assert isinstance(column.type, EncryptedText), column


@pytest.fixture()
def enc_session(monkeypatch, tmp_path):
    """ENCRYPTION_KEY 를 켠 격리 DB 세션. 설정 캐시를 앞뒤로 초기화한다."""
    monkeypatch.setenv("ENCRYPTION_KEY", Fernet.generate_key().decode())
    get_settings.cache_clear()
    crypto._get_fernet.cache_clear()

    engine = create_engine(f"sqlite:///{tmp_path}/enc.db")
    models.Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session
    engine.dispose()
    get_settings.cache_clear()
    crypto._get_fernet.cache_clear()


def test_db_stores_ciphertext_orm_returns_plaintext(enc_session):
    user = models.User(email="enc@test.com", password_hash="x", nickname="enc")
    enc_session.add(user)
    enc_session.flush()
    moment = models.Moment(user_id=user.id, date=date(2026, 7, 8), text="아무에게도 말 못한 고민")
    enc_session.add(moment)
    enc_session.commit()

    raw = enc_session.execute(sql_text("SELECT text FROM moments")).scalar_one()
    assert raw.startswith("gAAAA")
    assert "고민" not in raw

    enc_session.expire_all()
    assert enc_session.get(models.Moment, moment.id).text == "아무에게도 말 못한 고민"


def test_legacy_plaintext_row_still_readable(enc_session):
    """암호화 도입 전에 저장된 평문 행은 그대로 읽혀야 한다 (전환기 호환)."""
    enc_session.execute(sql_text(
        "INSERT INTO moments (id, user_id, date, text, created_at) "
        "VALUES ('m1', 'u1', '2026-07-01', '평문으로 저장된 옛 기록', '2026-07-01 00:00:00')"
    ))
    enc_session.commit()

    assert enc_session.get(models.Moment, "m1").text == "평문으로 저장된 옛 기록"
