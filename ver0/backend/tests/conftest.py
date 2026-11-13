"""테스트 픽스처: 임시 DB + mock AI + TestClient."""
import io
import os
import tempfile

import pytest

# 앱 import 전에 테스트 환경 강제
_tmpdir = tempfile.mkdtemp()
os.environ["DATABASE_URL"] = f"sqlite:///{_tmpdir}/test.db"
os.environ["AI_PROVIDER"] = "mock"
os.environ["GEMINI_API_KEY"] = ""
os.environ["UPLOAD_DIR"] = f"{_tmpdir}/uploads"
os.environ["APP_ENV"] = "dev"
os.environ["WEATHER_ENABLED"] = "false"  # 테스트에서 외부 호출 금지

from fastapi.testclient import TestClient  # noqa: E402
from PIL import Image  # noqa: E402

from app.main import app  # noqa: E402


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="session")
def token(client):
    res = client.post("/auth/signup", json={
        "email": "test@todaysfilm.app",
        "password": "password123",
        "nickname": "테스터",
    })
    assert res.status_code == 201, res.text
    return res.json()["access_token"]


@pytest.fixture(scope="session")
def auth(token):
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def jpeg_bytes():
    img = Image.new("RGB", (600, 400), (180, 140, 100))
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    return buf.getvalue()


def make_record(client, auth, jpeg, date, answer):
    """헬퍼: 사진 업로드→기록→질문/답변→필름 생성까지 한 번에."""
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("a.jpg", jpeg, "image/jpeg"))])
    assert res.status_code == 201, res.text
    photo_id = res.json()[0]["id"]

    res = client.post("/records", headers=auth, json={
        "date": date, "photo_ids": [photo_id], "main_photo_id": photo_id,
    })
    assert res.status_code == 201, res.text
    rid = res.json()["id"]

    q = client.post(f"/records/{rid}/questions", headers=auth,
                    json={"regenerate": False}).json()
    res = client.post(f"/records/{rid}/answers", headers=auth, json={
        "question_id": q["id"], "answer_text": answer, "skipped": False,
    })
    assert res.status_code == 201, res.text

    res = client.post(f"/records/{rid}/film", headers=auth)
    assert res.status_code == 200, res.text
    return rid, res.json()
