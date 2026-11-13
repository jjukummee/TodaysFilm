"""Mock 프로바이더. API 키 없이 개발/테스트/프론트 연동할 때 사용.

.env 에서 AI_PROVIDER=mock 으로 설정하거나, GEMINI_API_KEY가 비어 있으면 자동 사용.
임베딩은 문자 3-gram 해시 기반 가짜 벡터라서, 겹치는 표현이 많을수록
유사도가 높게 나온다 (기억 연결 로직을 키 없이도 테스트 가능).
"""
import hashlib
import math

from .base import AIProvider, FilmOutput, QAItem, ReportOutput

_QUESTIONS = {
    1: "이 사진을 오늘의 대표 장면으로 고른 이유가 있을까요?",
    2: "그 순간에서 가장 오래 기억하고 싶은 것은 무엇인가요?",
    3: "오늘 하루를 영화의 한 장면으로 남긴다면 어떤 장면으로 기억하고 싶나요?",
}

_REGEN_QUESTIONS = {
    1: "오늘의 장면 중 이 사진이 가장 먼저 떠오른 이유가 궁금해요.",
    2: "사진 속 순간을 다시 떠올리면 가장 먼저 생각나는 말은 무엇인가요?",
    3: "오늘의 나에게 제목을 붙인다면 어떤 제목이 어울릴까요?",
}

_EMBED_DIM = 128


class MockProvider(AIProvider):
    def analyze_photo(self, image: bytes) -> dict:
        return {
            "scene": "실내",
            "objects": ["테이블", "창문"],
            "people_present": False,
            "mood_hint": "따뜻한 오후",
        }

    def generate_question(self, images, history, question_order, question_type, avoid_question, context=None):
        if question_type == "recall":
            return "[MOCK-recall] 그때의 나에게 지금 한마디를 남긴다면 어떤 말일까요?"
        table = _REGEN_QUESTIONS if avoid_question else _QUESTIONS
        q = table.get(question_order, _QUESTIONS[3])
        if context and question_order == 1:
            q = f"[MOCK-ctx] {q}"  # 컨텍스트가 전달됐는지 테스트용 표시
        return q

    def generate_film(self, history: list[QAItem], context: str | None = None) -> FilmOutput:
        answered = [h.answer for h in history if not h.skipped and h.answer.strip()]
        rep = max(answered, key=len) if answered else "오늘의 장면을 조용히 남긴 하루였다."
        return FilmOutput(
            film_title="[MOCK] 오늘의 필름 제목",
            ending_narration="[MOCK] 오늘 하루의 장면이 조용히 필름에 담겼다.",
            representative_sentence=rep,
            keywords=["오늘", "기록", "장면"],
        )

    def generate_link_sentence(self, past_date, past_summary, current_summary):
        return f"[MOCK] {past_date}에 남겼던 기록과 조금 이어지는 부분이 있어요."

    def embed(self, text: str) -> list[float]:
        vec = [0.0] * _EMBED_DIM
        for i in range(len(text) - 2):
            gram = text[i : i + 3]
            idx = int(hashlib.md5(gram.encode()).hexdigest(), 16) % _EMBED_DIM
            vec[idx] += 1.0
        norm = math.sqrt(sum(v * v for v in vec)) or 1.0
        return [v / norm for v in vec]

    def transcribe(self, audio: bytes, mime_type: str) -> str:
        return "[MOCK] 오늘은 친구랑 카페에 다녀왔고 오랜만에 많이 웃었다."

    def generate_report(self, period_label: str, entries: list[dict]) -> ReportOutput:
        all_keywords: list[str] = []
        for e in entries:
            all_keywords.extend(e.get("keywords", []))
        return ReportOutput(
            report_title=f"[MOCK] {period_label}의 필름",
            narration=f"[MOCK] {period_label} 동안 {len(entries)}개의 장면이 쌓였다.",
            highlights=[e.get("representative_sentence") or "" for e in entries[:3]],
            keywords=list(dict.fromkeys(all_keywords))[:6],
        )
