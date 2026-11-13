"""최종 개발 PRD 정합화 동작 테스트.

- EXIF 제거 + 재인코딩 (8장)
- quote 원문 검증 + quote_candidates (6.3, 원칙 #4)
- 답변 0개 finalize → 이어서 회고하기 (6.3·7장)
- Vision 맥락 ai_context 저장 (6.1)
- 질문 생성 실패 시 폴백 질문 풀 (7장)
"""
import io

from PIL import Image

from app.ai.base import AIUnavailableError
from app.ai.mock import MockProvider
from app.ai.prompts import FALLBACK_QUESTIONS
from app.services.reflection import quote_candidates_from, quote_is_from_answers

from .conftest import make_record


# ─── EXIF 제거 + 재인코딩 (개발 PRD 8장) ────────────────
def test_upload_strips_exif_and_resizes(client, auth):
    img = Image.new("RGB", (3000, 2000), (120, 120, 120))
    exif = Image.Exif()
    exif[271] = "TestCam"  # 0x010F Make — 저장 후 남아 있으면 안 됨
    buf = io.BytesIO()
    img.save(buf, "JPEG", exif=exif)

    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("gps.jpg", buf.getvalue(), "image/jpeg"))])
    assert res.status_code == 201

    stored = client.get(res.json()[0]["url"], headers=auth).content
    with Image.open(io.BytesIO(stored)) as saved:
        assert dict(saved.getexif()) == {}          # 메타데이터 제거
        assert max(saved.size) <= 2048              # photo_max_side_storage 리사이즈


def test_upload_rejects_undecodable_image(client, auth):
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("fake.jpg", b"not-an-image", "image/jpeg"))])
    assert res.status_code == 400


# ─── quote 원문 검증 (개발 PRD 원칙 #4) ─────────────────
def test_quote_validation_helpers():
    answers = ["오늘은 조용한 하루였다. 그래도 노을이 좋았다", "친구랑 오랜만에 웃었다"]
    # 원문 문장 → 통과
    assert quote_is_from_answers("그래도 노을이 좋았다", answers)
    # LLM 이 지어낸 문장 → 거부
    assert not quote_is_from_answers("마음이 몽글몽글해진 하루였다", answers)
    assert not quote_is_from_answers("", answers)
    # 후보는 답변 원문 문장들
    candidates = quote_candidates_from(answers)
    assert "오늘은 조용한 하루였다" in candidates
    assert "친구랑 오랜만에 웃었다" in candidates


def test_film_returns_quote_from_answers_with_candidates(client, auth, jpeg_bytes):
    answer = "퇴근길 버스에서 노을을 봤다"
    _, film = make_record(client, auth, jpeg_bytes, "2026-06-01", answer)
    # mock 은 가장 긴 답변을 quote 로 반환 → 원문 검증 통과해야 함
    assert film["representative_sentence"] == answer
    assert answer in film["quote_candidates"]


def test_patch_quote_must_be_answer_sentence(client, auth, jpeg_bytes):
    answer = "도서관에서 하루를 보냈다"
    rid, _ = make_record(client, auth, jpeg_bytes, "2026-06-02", answer)
    # 답변에 없는 문장으로 교체 → 400
    res = client.patch(f"/records/{rid}", headers=auth,
                       json={"representative_sentence": "AI가 지어낸 문장"})
    assert res.status_code == 400
    # 답변 원문 문장으로 교체 → 200 (제목은 자유 수정)
    res = client.patch(f"/records/{rid}", headers=auth,
                       json={"representative_sentence": answer, "film_title": "내가 고친 제목"})
    assert res.status_code == 200
    assert res.json()["representative_sentence"] == answer


# ─── 답변 0개 finalize (개발 PRD 6.3·7장) ───────────────
def test_zero_answer_finalize_keeps_in_progress(client, auth, jpeg_bytes):
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("a.jpg", jpeg_bytes, "image/jpeg"))])
    pid = res.json()[0]["id"]
    rid = client.post("/records", headers=auth, json={
        "date": "2026-06-03", "photo_ids": [pid], "main_photo_id": pid,
    }).json()["id"]
    q = client.post(f"/records/{rid}/questions", headers=auth, json={"regenerate": False}).json()
    client.post(f"/records/{rid}/answers", headers=auth,
                json={"question_id": q["id"], "skipped": True})

    res = client.post(f"/records/{rid}/film", headers=auth)
    assert res.status_code == 200
    film = res.json()
    assert film["film_title"]                        # 중립 제목은 생성됨
    assert film["representative_sentence"] is None   # 인용할 원문이 없음 (원칙 #4)

    detail = client.get(f"/records/{rid}", headers=auth).json()
    assert detail["status"] == "in_progress"         # "이어서 회고하기" 유지


# ─── Vision 맥락 저장 (개발 PRD 6.1) ────────────────────
def test_first_question_stores_ai_context(client, auth, jpeg_bytes):
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("a.jpg", jpeg_bytes, "image/jpeg"))])
    pid = res.json()[0]["id"]
    rid = client.post("/records", headers=auth, json={
        "date": "2026-06-04", "photo_ids": [pid], "main_photo_id": pid,
    }).json()["id"]
    client.post(f"/records/{rid}/questions", headers=auth, json={"regenerate": False})

    from app import models
    from app.database import SessionLocal
    with SessionLocal() as db:
        photo = db.get(models.Photo, pid)
        assert photo.ai_context and "scene" in photo.ai_context  # 저장됨
    # 사용자 비노출: 상세 응답 photos 에 ai_context 없어야 함
    detail = client.get(f"/records/{rid}", headers=auth).json()
    assert all("ai_context" not in p for p in detail["photos"])


# ─── 질문 생성 실패 폴백 (개발 PRD 7장) ─────────────────
def test_question_fallback_when_ai_unavailable(client, auth, jpeg_bytes, monkeypatch):
    def _boom(*args, **kwargs):
        raise AIUnavailableError("simulated outage")

    monkeypatch.setattr(MockProvider, "generate_question", _boom)
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("a.jpg", jpeg_bytes, "image/jpeg"))])
    pid = res.json()[0]["id"]
    rid = client.post("/records", headers=auth, json={
        "date": "2026-06-05", "photo_ids": [pid], "main_photo_id": pid,
    }).json()["id"]

    res = client.post(f"/records/{rid}/questions", headers=auth, json={"regenerate": False})
    assert res.status_code == 200
    assert res.json()["question_text"] in FALLBACK_QUESTIONS[1]
