"""API 요청/응답 스키마 (Pydantic)."""
from datetime import date as DateType  # 'date' 필드명과의 충돌 방지용 별칭
from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


# ─── 인증 ─────────────────────────────────────────────
class SignupRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=100)
    nickname: str = Field(min_length=1, max_length=50)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: str
    email: str
    nickname: str

    model_config = {"from_attributes": True}


class UserStats(BaseModel):
    """마이페이지 통계 (필름 수 / 연속 기록 / 받은 질문)."""
    total_films: int
    streak_days: int
    questions_received: int


class UserUpdateRequest(BaseModel):
    """프로필 수정 (현재는 닉네임만)."""
    nickname: str = Field(min_length=1, max_length=50)


class UserSettingsOut(BaseModel):
    recall_enabled: bool
    reminder_time: str | None  # [FUTURE] HH:MM — 발송 인프라 도입 전까지 저장만

    model_config = {"from_attributes": True}


class UserSettingsUpdate(BaseModel):
    recall_enabled: bool | None = None
    reminder_time: str | None = Field(default=None, pattern=r"^([01]\d|2[0-3]):[0-5]\d$")


# ─── 사진 ─────────────────────────────────────────────
class PhotoOut(BaseModel):
    id: str
    url: str
    is_main: bool


# ─── 회고 기록 ─────────────────────────────────────────
class LocationIn(BaseModel):
    """위치 정보 (3차: 위치/날씨 기반 회고 보조). 클라이언트가 GPS/장소명을 보낸다."""
    name: str | None = Field(default=None, max_length=200)  # 예: "연남동 카페"
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)


class RecordCreateRequest(BaseModel):
    # 미지정 시 오늘(Asia/Seoul). 자정 넘긴 새벽 회고는 클라이언트가 어제 날짜로 보낼 수 있음.
    date: DateType | None = None
    photo_ids: list[str] = Field(min_length=1, max_length=5)  # PRD 7.1: 1~5장
    main_photo_id: str
    location: LocationIn | None = None  # 선택 사항 (3차)


class QuestionRequest(BaseModel):
    regenerate: bool = False  # true면 마지막 미답변 질문을 다시 생성


class RecallPreview(BaseModel):
    """recall형 질문이 가리키는 과거 기록 미리보기 (개발 PRD 6.4 recall 객체)."""
    past_record_id: str
    past_date: DateType
    film_title: str | None
    representative_sentence: str | None


class QuestionOut(BaseModel):
    id: str
    question_order: int
    question_text: str
    question_type: str
    recall: RecallPreview | None = None  # question_type == "recall" 일 때만 채워짐

    model_config = {"from_attributes": True}


class AnswerRequest(BaseModel):
    question_id: str
    answer_text: str = Field(default="", max_length=2000)  # LLM 토큰 가드레일
    skipped: bool = False


class AnswerOut(BaseModel):
    id: str
    question_id: str
    answer_text: str
    skipped: bool
    # 위기 표현 감지 시 도움 정보 안내 (서비스 PRD 17장). 저장되지 않는 응답 전용 필드.
    safety_notice: str | None = None

    model_config = {"from_attributes": True}


class AnswerUpdateRequest(BaseModel):
    answer_text: str = Field(max_length=2000)


# ─── 필름 결과 ─────────────────────────────────────────
class MemoryLinkOut(BaseModel):
    past_record_id: str
    past_date: DateType
    link_reason: str
    link_sentence: str


class FilmResult(BaseModel):
    film_title: str
    ending_narration: str
    representative_sentence: str | None  # 답변 0개면 None (quote 는 사용자 원문만 — 원칙 #4)
    keywords: list[str]
    # 기억 문장 교체 후보 — 사용자 답변 원문 문장들 (개발 PRD 6.3)
    quote_candidates: list[str] = []
    memory_link: MemoryLinkOut | None = None


class RecordUpdateRequest(BaseModel):
    """생성 결과 수동 수정 (PRD 7.3: 사용자는 수정할 수 있다)."""
    film_title: str | None = None
    ending_narration: str | None = None
    representative_sentence: str | None = None
    # "다시 꺼내지 않기" — 이 기록을 회상 대상에서 제외 (서비스 PRD 17장)
    recall_blocked: bool | None = None


class RecordDetail(BaseModel):
    id: str
    date: DateType
    status: str
    recall_blocked: bool = False
    film_title: str | None
    ending_narration: str | None
    representative_sentence: str | None
    keywords: list[str]
    photos: list[PhotoOut]
    questions: list[QuestionOut]
    answers: list[AnswerOut]
    memory_links: list[MemoryLinkOut]
    location_name: str | None = None
    weather_summary: str | None = None
    created_at: datetime


# ─── 아카이브 ─────────────────────────────────────────
class ArchiveDay(BaseModel):
    date: DateType
    record_id: str
    film_title: str | None
    representative_sentence: str | None = None
    main_photo_url: str | None


class ArchiveMonth(BaseModel):
    year: int
    month: int
    record_count: int
    days: list[ArchiveDay]


# ─── 순간 기록 (3차) ───────────────────────────────────
class MomentCreateRequest(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    date: DateType | None = None  # 미지정 시 오늘(Asia/Seoul)
    photo_id: str | None = None


class MomentOut(BaseModel):
    id: str
    date: DateType
    text: str
    photo_id: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


# ─── 음성 입력 (3차) ───────────────────────────────────
class TranscriptionOut(BaseModel):
    text: str


# ─── 필름 공유 (확장 — routers/share.py) ────────────────
class ShareLinkOut(BaseModel):
    token: str
    url: str  # 공개 조회 경로 (예: /share/{token})


class SharedFilmOut(BaseModel):
    """공유 링크로 공개되는 필름 정보.

    개발 PRD 8장: 대화 원문·기억 포인트(키워드)·위치는 원천 제외.
    여기에 필드를 추가할 때는 반드시 공개 가능 여부를 먼저 검토할 것.
    """
    date: DateType
    film_title: str | None
    ending_narration: str | None
    representative_sentence: str | None
    nickname: str
    photo_url: str | None  # 대표 사진 공개 접근 경로


# ─── 월간/연간 리포트 (3차) ─────────────────────────────
class ReportOut(BaseModel):
    period_type: str          # monthly | yearly
    period_key: str           # "2026-07" | "2026"
    report_title: str
    narration: str
    highlights: list[str]
    keywords: list[str]
    record_count: int
    created_at: datetime
