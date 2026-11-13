"""AI 프로바이더 추상 인터페이스.

★모델 교체 지점★
새 프로바이더(Claude, GPT 등)를 붙이려면:
  1. 이 클래스를 상속한 구현체를 만들고 (gemini.py 참고)
  2. factory.py 에 등록하고
  3. .env 의 AI_PROVIDER 값만 바꾸면 끝.
라우터/서비스 코드는 전혀 수정할 필요 없음.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field


class AIUnavailableError(Exception):
    """LLM 호출이 재시도 후에도 실패했을 때. main.py 에서 502로 변환된다."""


@dataclass
class QAItem:
    """질문-답변 한 쌍 (대화 히스토리용)."""
    question: str
    answer: str
    skipped: bool = False


@dataclass
class FilmOutput:
    """필름 생성 결과 (PRD 7.4)."""
    film_title: str
    ending_narration: str
    representative_sentence: str
    keywords: list[str] = field(default_factory=list)


@dataclass
class ReportOutput:
    """월간/연간 회고 리포트 (PRD 16.3)."""
    report_title: str        # 예: "7월, 조금씩 단단해진 달"
    narration: str           # 기간 전체를 묶는 내레이션 2~3문장
    highlights: list[str]    # 기억에 남는 장면 문장 2~4개
    keywords: list[str]      # 기간 대표 키워드


class AIProvider(ABC):
    """오늘의 필름이 AI에 요구하는 능력 목록."""

    # ─── 핵심 (1차) ─────────────────────────────────
    @abstractmethod
    def analyze_photo(self, image: bytes) -> dict:
        """사진 맥락 파악 (개발 PRD 6.1 Vision 단계).

        반환 JSON: scene / objects / people_present(bool) / mood_hint.
        질문 생성의 단서로만 쓰이고 사용자에게 노출되지 않는다.
        인원수·관계 추정 금지."""

    @abstractmethod
    def generate_question(
        self,
        images: list[bytes],          # 리사이즈된 JPEG 바이트 (첫 질문에만 전달됨)
        history: list[QAItem],        # 이전 질문/답변
        question_order: int,          # 1~3 (PRD 7.2 질문 3단계 구조)
        question_type: str,           # photo_reason | moment_meaning | memory_point ...
        avoid_question: str | None,   # "다시 받기" 시 피해야 할 직전 질문
        context: str | None = None,   # 순간 기록/장소/날씨 등 참고 정보 (3차 기능)
    ) -> str:
        """회고 질문 한 개를 생성한다."""

    @abstractmethod
    def generate_film(self, history: list[QAItem], context: str | None = None) -> FilmOutput:
        """답변들을 바탕으로 제목/내레이션/대표 문장/키워드를 생성한다.

        context: 사진 맥락 등 참고 정보 (개발 PRD 6.3 입력: 전체 대화 + 사진 맥락).
        답변이 하나도 없으면 사진 맥락만으로 중립적 제목을 만든다."""

    @abstractmethod
    def generate_link_sentence(
        self,
        past_date: str,
        past_summary: str,
        current_summary: str,
    ) -> str | None:
        """과거↔현재 기록 연결 문장. 명확한 연결점이 없으면 None (PRD 10.3)."""

    # ─── 3차 기능 ───────────────────────────────────
    @abstractmethod
    def embed(self, text: str) -> list[float]:
        """텍스트 임베딩 벡터. 고도화된 기억 연결(의미 기반 유사도 검색)에 사용."""

    @abstractmethod
    def transcribe(self, audio: bytes, mime_type: str) -> str:
        """음성 → 텍스트 전사 (음성 입력 기능)."""

    @abstractmethod
    def generate_report(self, period_label: str, entries: list[dict]) -> ReportOutput:
        """월간/연간 리포트 생성. entries: [{date, film_title, representative_sentence, keywords}]"""
