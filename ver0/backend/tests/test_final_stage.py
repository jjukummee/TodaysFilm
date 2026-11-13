"""최종 개발 단계 기능 테스트.

- recall 대화 중 질문 대체 + 회고당 1회 링크 (개발 PRD 6.4)
- 회상 차단(recall_blocked) / 회상 설정(recall_enabled) (서비스 PRD 17장)
- 위기 표현 안내 (서비스 PRD 17장)
- 프로필 수정 / 사용자 설정 / 데이터 내보내기
- [FUTURE] 공유 링크 (대화 원문 원천 제외)
"""

# 3-gram mock 임베딩에서 확실히 임계값(0.55)을 넘도록 길고 동일한 문장 사용
SIMILAR = "요즘 취업 준비 때문에 걱정이 많고 마음이 무거운 하루였다 취업 걱정이 머리를 떠나지 않는다"


def _start_record(client, auth, jpeg, date):
    res = client.post("/photos/upload", headers=auth,
                      files=[("files", ("a.jpg", jpeg, "image/jpeg"))])
    pid = res.json()[0]["id"]
    rid = client.post("/records", headers=auth, json={
        "date": date, "photo_ids": [pid], "main_photo_id": pid,
    }).json()["id"]
    return rid


def _ask_and_answer(client, auth, rid, answer):
    q = client.post(f"/records/{rid}/questions", headers=auth, json={"regenerate": False}).json()
    client.post(f"/records/{rid}/answers", headers=auth, json={
        "question_id": q["id"], "answer_text": answer, "skipped": False,
    })
    return q


# ─── recall: 대화 중 마지막 질문 대체 (개발 PRD 6.4) ────
def test_recall_question_replaces_closing(client, auth, jpeg_bytes):
    # 1) 과거 기록 심기 (2026-05-01, 취업 고민)
    past_rid = _start_record(client, auth, jpeg_bytes, "2026-05-01")
    _ask_and_answer(client, auth, past_rid, SIMILAR)
    assert client.post(f"/records/{past_rid}/film", headers=auth).status_code == 200

    # 2) 19일 뒤, 비슷한 이야기로 회고 진행
    rid = _start_record(client, auth, jpeg_bytes, "2026-05-20")
    _ask_and_answer(client, auth, rid, SIMILAR)
    _ask_and_answer(client, auth, rid, SIMILAR)

    # 3) 마지막 질문이 recall형으로 대체되고 과거 기록 미리보기가 붙는다
    q3 = client.post(f"/records/{rid}/questions", headers=auth, json={"regenerate": False}).json()
    assert q3["question_type"] == "recall"
    assert q3["recall"]["past_record_id"] == past_rid

    # 4) recall 질문에 답하면(반응) 결과물에 그 연결이 포함된다 — 회고당 1회
    client.post(f"/records/{rid}/answers", headers=auth, json={
        "question_id": q3["id"], "answer_text": "그때보다는 마음이 단단해졌다", "skipped": False,
    })
    film = client.post(f"/records/{rid}/film", headers=auth).json()
    assert film["memory_link"]["past_record_id"] == past_rid
    assert film["memory_link"]["link_reason"] == "recall_question"


def test_recall_disabled_by_user_setting(client, auth, jpeg_bytes):
    # 회상 기능 끄기 (서비스 PRD 17장 — 기억 통제권)
    res = client.patch("/auth/me/settings", headers=auth, json={"recall_enabled": False})
    assert res.status_code == 200 and res.json()["recall_enabled"] is False

    rid = _start_record(client, auth, jpeg_bytes, "2026-05-24")
    _ask_and_answer(client, auth, rid, SIMILAR)
    _ask_and_answer(client, auth, rid, SIMILAR)
    q3 = client.post(f"/records/{rid}/questions", headers=auth, json={"regenerate": False}).json()
    assert q3["question_type"] != "recall"

    client.patch("/auth/me/settings", headers=auth, json={"recall_enabled": True})  # 원복


def test_recall_blocked_record_excluded(client, auth, jpeg_bytes):
    # 취업 이야기가 담긴 완성 기록들을 전부 "다시 꺼내지 않기"
    for day in client.get("/archive/calendar?year=2026&month=5", headers=auth).json()["days"]:
        res = client.patch(f"/records/{day['record_id']}", headers=auth,
                           json={"recall_blocked": True})
        assert res.status_code == 200 and res.json()["recall_blocked"] is True

    rid = _start_record(client, auth, jpeg_bytes, "2026-05-27")
    _ask_and_answer(client, auth, rid, SIMILAR)
    _ask_and_answer(client, auth, rid, SIMILAR)
    q3 = client.post(f"/records/{rid}/questions", headers=auth, json={"regenerate": False}).json()
    assert q3["question_type"] != "recall"  # 차단된 기록은 회상 후보에서 제외


# ─── 위기 표현 안내 (서비스 PRD 17장) ───────────────────
def test_crisis_answer_returns_safety_notice(client, auth, jpeg_bytes):
    rid = _start_record(client, auth, jpeg_bytes, "2026-04-01")
    q = client.post(f"/records/{rid}/questions", headers=auth, json={"regenerate": False}).json()
    res = client.post(f"/records/{rid}/answers", headers=auth, json={
        "question_id": q["id"], "answer_text": "요즘은 자꾸 죽고 싶다는 생각이 들어", "skipped": False,
    })
    assert res.status_code == 201
    assert res.json()["safety_notice"]  # 판단 없이 도움 정보 안내


def test_normal_answer_has_no_notice(client, auth, jpeg_bytes):
    rid = _start_record(client, auth, jpeg_bytes, "2026-04-02")
    q = client.post(f"/records/{rid}/questions", headers=auth, json={"regenerate": False}).json()
    res = client.post(f"/records/{rid}/answers", headers=auth, json={
        "question_id": q["id"], "answer_text": "오늘 하루를 잘 끝내고 싶다", "skipped": False,
    })
    assert res.json()["safety_notice"] is None


# ─── 프로필 / 설정 / 내보내기 ───────────────────────────
def test_update_nickname(client, auth):
    res = client.patch("/auth/me", headers=auth, json={"nickname": "새닉네임"})
    assert res.status_code == 200 and res.json()["nickname"] == "새닉네임"
    client.patch("/auth/me", headers=auth, json={"nickname": "테스터"})  # 원복


def test_settings_reminder_time_set_and_clear(client, auth):
    res = client.patch("/auth/me/settings", headers=auth, json={"reminder_time": "22:30"})
    assert res.json()["reminder_time"] == "22:30"
    res = client.patch("/auth/me/settings", headers=auth, json={"reminder_time": None})
    assert res.json()["reminder_time"] is None
    # 형식 검증
    assert client.patch("/auth/me/settings", headers=auth,
                        json={"reminder_time": "25:99"}).status_code == 422


def test_reminder_stub_targets_users(client, auth):
    """[FUTURE] notifications.send_evening_reminders — 시각 일치 + 오늘 미기록 사용자만."""
    from app.database import SessionLocal
    from app.services.notifications import send_evening_reminders

    client.patch("/auth/me/settings", headers=auth, json={"reminder_time": "21:45"})
    with SessionLocal() as db:
        assert send_evening_reminders(db, now_hhmm="21:45") >= 1
        assert send_evening_reminders(db, now_hhmm="03:33") == 0  # 일치하는 사용자 없음
    client.patch("/auth/me/settings", headers=auth, json={"reminder_time": None})  # 원복


def test_export_contains_records_and_conversations(client, auth):
    res = client.get("/auth/me/export", headers=auth)
    assert res.status_code == 200
    data = res.json()
    assert data["user"]["email"] == "test@todaysfilm.app"
    assert len(data["records"]) >= 1
    assert any(r["answers"] for r in data["records"])  # 대화(답변)까지 포함


# ─── [FUTURE] 공유 링크 ─────────────────────────────────
def test_share_link_flow_excludes_private_data(client, auth, jpeg_bytes):
    from .conftest import make_record

    rid, _ = make_record(client, auth, jpeg_bytes, "2026-04-10", "공유하고 싶은 하루였다")
    token = client.post(f"/records/{rid}/share", headers=auth).json()["token"]

    # 무인증 공개 조회 — 대화 원문·키워드·위치는 절대 포함되지 않는다 (개발 PRD 8장)
    res = client.get(f"/share/{token}")
    assert res.status_code == 200
    body = res.json()
    assert body["representative_sentence"] == "공유하고 싶은 하루였다"
    assert set(body) == {
        "date", "film_title", "ending_narration", "representative_sentence", "nickname", "photo_url",
    }

    # 대표 사진도 무인증으로 열람 가능
    assert client.get(body["photo_url"]).status_code == 200

    # 회수(revoke) 후에는 404
    assert client.delete(f"/records/{rid}/share", headers=auth).status_code == 204
    assert client.get(f"/share/{token}").status_code == 404


def test_share_requires_completed_film(client, auth, jpeg_bytes):
    rid = _start_record(client, auth, jpeg_bytes, "2026-04-11")  # in_progress
    assert client.post(f"/records/{rid}/share", headers=auth).status_code == 400
