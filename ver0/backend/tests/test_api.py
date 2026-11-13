"""전체 API 통합 테스트 (mock AI 기준).

실행: cd backend && python -m pytest tests/ -q
"""
from datetime import date

from .conftest import make_record


# ─── 인증 ───────────────────────────────────────────
def test_signup_duplicate_rejected(client, token):
    res = client.post("/auth/signup", json={
        "email": "test@todaysfilm.app", "password": "password123", "nickname": "x",
    })
    assert res.status_code == 409


def test_login_wrong_password(client):
    res = client.post("/auth/login", json={
        "email": "test@todaysfilm.app", "password": "wrong-password",
    })
    assert res.status_code == 401


def test_me_requires_token(client):
    assert client.get("/auth/me").status_code == 401


def test_me(client, auth):
    res = client.get("/auth/me", headers=auth)
    assert res.status_code == 200
    assert res.json()["nickname"] == "테스터"


# ─── 회고 플로우 ─────────────────────────────────────
def test_full_reflection_flow(client, auth, jpeg_bytes):
    rid, film = make_record(client, auth, jpeg_bytes, "2026-07-01", "오늘은 조용한 하루였다")
    assert film["film_title"]
    assert film["representative_sentence"]
    assert isinstance(film["keywords"], list)

    detail = client.get(f"/records/{rid}", headers=auth).json()
    assert detail["status"] == "completed"
    assert len(detail["photos"]) == 1


def test_one_film_per_day(client, auth, jpeg_bytes):
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("a.jpg", jpeg_bytes, "image/jpeg"))])
    pid = res.json()[0]["id"]
    res = client.post("/records", headers=auth, json={
        "date": "2026-07-01", "photo_ids": [pid], "main_photo_id": pid,
    })
    assert res.status_code == 409  # 하루 1필름


def test_question_limit(client, auth, jpeg_bytes):
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("a.jpg", jpeg_bytes, "image/jpeg"))])
    pid = res.json()[0]["id"]
    rid = client.post("/records", headers=auth, json={
        "date": "2026-07-02", "photo_ids": [pid], "main_photo_id": pid,
    }).json()["id"]

    for i in range(3):
        q = client.post(f"/records/{rid}/questions", headers=auth,
                        json={"regenerate": False}).json()
        client.post(f"/records/{rid}/answers", headers=auth, json={
            "question_id": q["id"], "answer_text": f"답변 {i}", "skipped": False,
        })
    res = client.post(f"/records/{rid}/questions", headers=auth,
                      json={"regenerate": False})
    assert res.status_code == 400  # 3개 초과 거부


def test_answer_too_long_rejected(client, auth, jpeg_bytes):
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("a.jpg", jpeg_bytes, "image/jpeg"))])
    pid = res.json()[0]["id"]
    rid = client.post("/records", headers=auth, json={
        "date": "2026-07-03", "photo_ids": [pid], "main_photo_id": pid,
    }).json()["id"]
    q = client.post(f"/records/{rid}/questions", headers=auth,
                    json={"regenerate": False}).json()
    res = client.post(f"/records/{rid}/answers", headers=auth, json={
        "question_id": q["id"], "answer_text": "가" * 3000, "skipped": False,
    })
    assert res.status_code == 422  # max_length=2000


# ─── 사진 보안 ───────────────────────────────────────
def test_photo_file_requires_owner(client, auth, jpeg_bytes):
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("a.jpg", jpeg_bytes, "image/jpeg"))])
    url = res.json()[0]["url"]
    # 토큰 없이 → 401
    assert client.get(url).status_code == 401
    # 소유자 → 200
    assert client.get(url, headers=auth).status_code == 200
    # 다른 사용자 → 404
    other = client.post("/auth/signup", json={
        "email": "other@todaysfilm.app", "password": "password123", "nickname": "남",
    }).json()["access_token"]
    res = client.get(url, headers={"Authorization": f"Bearer {other}"})
    assert res.status_code == 404


def test_upload_rejects_bad_type(client, auth):
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("evil.exe", b"MZ...", "application/octet-stream"))])
    assert res.status_code == 400


# ─── 아카이브 / 통계 / 리포트 ─────────────────────────
def test_archive_calendar(client, auth):
    res = client.get("/archive/calendar?year=2026&month=7", headers=auth)
    assert res.status_code == 200
    assert res.json()["record_count"] >= 1


def test_my_stats(client, auth):
    res = client.get("/auth/me/stats", headers=auth)
    assert res.status_code == 200
    body = res.json()
    assert body["total_films"] >= 1
    assert "streak_days" in body


def test_monthly_report_needs_three_films(client, auth, jpeg_bytes):
    # 앞선 테스트에서 7/1 완성 1개 → 2개 더 만들어 3개 충족
    make_record(client, auth, jpeg_bytes, "2026-07-10", "한강을 걸었다")
    make_record(client, auth, jpeg_bytes, "2026-07-15", "동료들과 점심을 먹었다")
    res = client.get("/reports/monthly?year=2026&month=7", headers=auth)
    assert res.status_code == 200
    assert res.json()["record_count"] >= 3
    # 캐시 확인 (동일 created_at)
    again = client.get("/reports/monthly?year=2026&month=7", headers=auth)
    assert again.json()["created_at"] == res.json()["created_at"]


# ─── 순간 기록 / 음성 ─────────────────────────────────
def test_moments_crud(client, auth):
    res = client.post("/moments", headers=auth, json={"text": "점심의 짧은 메모"})
    assert res.status_code == 201
    mid = res.json()["id"]
    today = date.today().isoformat()
    res = client.get(f"/moments?date={today}", headers=auth)
    assert any(m["id"] == mid for m in res.json())
    assert client.delete(f"/moments/{mid}", headers=auth).status_code == 204


def test_voice_transcribe_mock(client, auth):
    res = client.post("/voice/transcribe", headers=auth,
                      files=[("file", ("memo.m4a", b"fake-audio", "audio/m4a"))])
    assert res.status_code == 200
    assert res.json()["text"]


# ─── 계정 삭제 ───────────────────────────────────────
def test_delete_account_cleans_up(client, jpeg_bytes):
    t = client.post("/auth/signup", json={
        "email": "gone@todaysfilm.app", "password": "password123", "nickname": "삭제",
    }).json()["access_token"]
    h = {"Authorization": f"Bearer {t}"}
    make_record(client, h, jpeg_bytes, "2026-07-20", "곧 사라질 기록")
    assert client.delete("/auth/me", headers=h).status_code == 204
    assert client.get("/auth/me", headers=h).status_code == 401
