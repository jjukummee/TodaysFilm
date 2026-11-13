"""Gemini 구현체. ★현재 사용 중인 프로바이더★

교체/추가 시 이 파일을 복사해서 다른 SDK로 바꾸면 된다.
예: Claude로 바꾸려면 anthropic SDK로 동일한 메서드들만 구현하면 됨.
     (base.py 의 AIProvider 인터페이스 참고)
"""
import json
import re

from .base import AIProvider, AIUnavailableError, FilmOutput, QAItem, ReportOutput
from . import prompts


def _extract_json(text: str) -> dict:
    """LLM 출력에서 JSON만 안전하게 추출."""
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        raise ValueError(f"JSON을 찾을 수 없음: {text[:200]}")
    return json.loads(match.group())


class GeminiProvider(AIProvider):
    def __init__(self, api_key: str, question_model: str, film_model: str, embedding_model: str):
        # 지연 import: mock 모드에서는 google-genai 설치 없이도 서버가 뜨도록
        from google import genai

        self._genai = genai
        self.client = genai.Client(api_key=api_key)
        # ★모델 교체 지점★ .env 의 GEMINI_*_MODEL
        self.question_model = question_model
        self.film_model = film_model
        self.embedding_model = embedding_model

    # ── 내부 공통 호출 (타임아웃 + 지수 백오프 재시도) ──
    def _call(self, model: str, system: str, contents: list) -> str:
        import time

        from google.genai import types

        from ..config import get_settings

        settings = get_settings()
        last_error: Exception | None = None
        for attempt in range(settings.ai_max_retries + 1):
            try:
                resp = self.client.models.generate_content(
                    model=model,
                    contents=contents,
                    config=types.GenerateContentConfig(
                        system_instruction=system,
                        temperature=0.8,
                        max_output_tokens=2048,
                        http_options=types.HttpOptions(
                            timeout=int(settings.ai_timeout_seconds * 1000)  # ms
                        ),
                    ),
                )
                return (resp.text or "").strip()
            except Exception as e:  # 일시 오류(429/5xx/타임아웃) 재시도
                last_error = e
                if attempt < settings.ai_max_retries:
                    time.sleep(1.5 * (2 ** attempt))  # 1.5s → 3s
        raise AIUnavailableError(str(last_error))

    # ── 0. 사진 맥락 파악 (Vision 별도 단계) ─────────
    def analyze_photo(self, image: bytes) -> dict:
        from google.genai import types

        parts = [types.Part.from_bytes(data=image, mime_type="image/jpeg"), prompts.VISION_PROMPT]
        raw = self._call(self.question_model, prompts.SYSTEM_VISION, parts)
        return _extract_json(raw)

    # ── 1. 회고 질문 생성 ───────────────────────────
    def generate_question(self, images, history, question_order, question_type, avoid_question, context=None):
        from google.genai import types

        stage = prompts.QUESTION_STAGES.get(question_order, prompts.QUESTION_STAGES[3])
        parts: list = []

        # 사진은 첫 질문에만 전달 (이후 질문은 답변 기반 → 비용 절감)
        for img in images:
            parts.append(types.Part.from_bytes(data=img, mime_type="image/jpeg"))

        # recall형은 순서 기반 가이드 대신 과거 연결 가이드 사용 (개발 PRD 6.4)
        text = prompts.RECALL_GUIDE if question_type == "recall" else stage["guide"]
        if context:
            # 3차 기능: 순간 기록/장소/날씨 참고 정보. 단정 금지 원칙 유지.
            text += f"\n\n참고 정보 (직접 언급은 자연스러울 때만, 단정하지 마라):\n{context}"
        if history:
            text += "\n\n지금까지의 대화:\n" + prompts.build_qa_block(history)
        if avoid_question:
            text += prompts.REGENERATE_SUFFIX.format(avoid=avoid_question)
        parts.append(text)

        question = self._call(self.question_model, prompts.SYSTEM_QUESTIONER, parts)
        return question.strip().strip('"').strip()

    # ── 2. 필름 결과 생성 ───────────────────────────
    def generate_film(self, history: list[QAItem], context: str | None = None) -> FilmOutput:
        prompt = prompts.FILM_GENERATION_PROMPT.format(qa_block=prompts.build_qa_block(history))
        if context:
            # 개발 PRD 6.3 입력: 전체 대화 + 사진 맥락. 답변 0개면 이 맥락만으로 중립 제목 생성.
            prompt = f"[사진 맥락 (참고용 — 단정하거나 감정을 추가하지 마라)]\n{context}\n\n{prompt}"
        raw = self._call(self.film_model, prompts.SYSTEM_FILM_WRITER, [prompt])
        try:
            data = _extract_json(raw)
        except (ValueError, json.JSONDecodeError):
            # 출력이 JSON이 아니면 한 번 더 강하게 요구 (드물지만 발생함)
            raw = self._call(
                self.film_model, prompts.SYSTEM_FILM_WRITER,
                [prompt + "\n\n반드시 유효한 JSON 객체 하나만 출력하라. 다른 텍스트 금지."],
            )
            data = _extract_json(raw)
        return FilmOutput(
            film_title=data.get("film_title", "").strip(),
            ending_narration=data.get("ending_narration", "").strip(),
            representative_sentence=data.get("representative_sentence", "").strip(),
            keywords=[k.strip() for k in data.get("keywords", []) if k.strip()][:5],
        )

    # ── 3. 과거 기록 연결 문장 ──────────────────────
    def generate_link_sentence(self, past_date, past_summary, current_summary):
        prompt = prompts.LINK_PROMPT.format(
            past_date=past_date, past_summary=past_summary, current_summary=current_summary
        )
        out = self._call(self.film_model, prompts.SYSTEM_LINKER, [prompt])
        if not out or out.strip().upper().startswith("NONE"):
            return None
        return out.strip()

    # ── 4. 임베딩 (3차: 고도화된 기억 연결) ──────────
    def embed(self, text: str) -> list[float]:
        resp = self.client.models.embed_content(model=self.embedding_model, contents=text)
        return list(resp.embeddings[0].values)

    # ── 5. 음성 전사 (3차: 음성 입력) ────────────────
    def transcribe(self, audio: bytes, mime_type: str) -> str:
        from google.genai import types

        parts = [types.Part.from_bytes(data=audio, mime_type=mime_type), prompts.TRANSCRIBE_PROMPT]
        return self._call(self.question_model, "너는 정확한 한국어 음성 전사기다.", parts)

    # ── 6. 월간/연간 리포트 (3차) ────────────────────
    def generate_report(self, period_label: str, entries: list[dict]) -> ReportOutput:
        prompt = prompts.REPORT_PROMPT.format(
            period_label=period_label, entries_block=prompts.build_entries_block(entries)
        )
        raw = self._call(self.film_model, prompts.SYSTEM_REPORT_WRITER, [prompt])
        data = _extract_json(raw)
        return ReportOutput(
            report_title=data.get("report_title", "").strip(),
            narration=data.get("narration", "").strip(),
            highlights=[h.strip() for h in data.get("highlights", []) if h.strip()][:4],
            keywords=[k.strip() for k in data.get("keywords", []) if k.strip()][:6],
        )
