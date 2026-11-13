"""SQLAlchemy 세션/엔진 설정."""
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import get_settings

settings = get_settings()

# SQLite는 스레드 체크 해제 필요 (FastAPI 멀티스레드)
connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
engine = create_engine(settings.database_url, connect_args=connect_args)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# 기존 테이블에 추가된 컬럼 목록: (테이블, 컬럼, DDL 타입)
# create_all 은 새 테이블만 만들고 기존 테이블은 건드리지 않으므로 여기서 보완한다.
_LIGHT_MIGRATIONS = [
    ("photos", "ai_context", "TEXT"),
    ("daily_film_records", "recall_blocked", "BOOLEAN DEFAULT 0"),
    ("ai_questions", "recall_record_id", "VARCHAR(32)"),
]


def run_light_migrations() -> None:
    """sqlite 개발 DB 전용 경량 마이그레이션.

    운영 PostgreSQL 전환 시 Alembic 으로 대체할 것 (main.py 주석 참고).
    """
    if engine.dialect.name != "sqlite":
        return
    from sqlalchemy import text

    with engine.connect() as conn:
        for table, column, ddl_type in _LIGHT_MIGRATIONS:
            cols = [row[1] for row in conn.execute(text(f"PRAGMA table_info({table})"))]
            if cols and column not in cols:
                conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {ddl_type}"))
        conn.commit()
