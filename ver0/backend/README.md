# 오늘의 필름 — 백엔드 (FastAPI)

하루 회고형 AI 사진 회고 서비스의 백엔드. **PRD 1차~3차 개발 범위(백엔드 몫) 전체 구현.**

| 단계 | 기능 | 상태 |
|---|---|---|
| 1차 | 회원가입/로그인, 사진 업로드, AI 질문, 답변 저장, 필름 생성, 아카이브 | ✅ |
| 2차 | 키워드 기억 연결, 검색, 월간 모아보기 | ✅ (카드 템플릿/공유 저장은 프론트 영역) |
| 3차 | 임베딩 기반 고도화 기억 연결, 순간 기록, 음성 입력(STT), 위치/날씨 회고 보조, 월간/연간 리포트 | ✅ |

## 빠른 시작

```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env    # GEMINI_API_KEY 입력 (없으면 mock 모드로 동작)
uvicorn app.main:app --reload
```

- API 문서(Swagger): http://localhost:8000/docs
- 헬스체크: `GET /health` → 현재 연결된 AI 프로바이더 확인 가능

## AI 모델 교체 방법 ★

**코드 전체에서 `★모델 교체 지점★` 주석을 검색하면 바꿀 곳이 다 나온다.**

| 바꾸고 싶은 것 | 수정 위치 |
|---|---|
| Gemini 모델 버전만 변경 | `.env` 의 `GEMINI_QUESTION_MODEL`, `GEMINI_FILM_MODEL` |
| 키 없이 개발 (mock) | `.env` 의 `AI_PROVIDER=mock` (키가 비어 있어도 자동 mock) |
| Claude 등 다른 벤더로 교체 | ① `app/ai/gemini.py` 를 복사해 새 구현체 작성 → ② `app/ai/factory.py` 에 분기 추가 → ③ `.env` 의 `AI_PROVIDER` 변경 |
| 질문/문체 튜닝 | `app/ai/prompts.py` (프롬프트는 전부 이 파일에만 있음) |

라우터·서비스 코드는 프로바이더를 모르는 구조라, 위 파일들 외에는 건드릴 필요 없음.

## 프로젝트 구조

```
backend/
├── app/
│   ├── main.py            # 엔트리포인트, 라우터 등록
│   ├── config.py          # 환경변수 설정
│   ├── database.py        # SQLAlchemy 세션
│   ├── models.py          # DB 모델 (PRD 9장)
│   ├── schemas.py         # 요청/응답 스키마
│   ├── security.py        # 비밀번호 해시 + JWT
│   ├── deps.py            # 인증 의존성
│   ├── routers/
│   │   ├── auth.py        # 회원가입/로그인/계정삭제
│   │   ├── photos.py      # 사진 업로드
│   │   ├── records.py     # 회고 기록 (질문→답변→필름 생성, 위치/날씨 포함)
│   │   ├── archive.py     # 캘린더/검색/과거의 오늘
│   │   ├── moments.py     # 순간 기록 (3차)
│   │   ├── voice.py       # 음성 입력 STT (3차)
│   │   └── reports.py     # 월간/연간 리포트 (3차)
│   ├── services/
│   │   ├── reflection.py  # 회고 오케스트레이션 (핵심 비즈니스 로직)
│   │   ├── embeddings.py  # 임베딩 저장/유사도 검색 (3차 기억 연결)
│   │   ├── reports.py     # 리포트 생성 + 캐시 (3차)
│   │   ├── weather.py     # Open-Meteo 날씨 조회 (3차, 키 불필요)
│   │   └── images.py      # LLM 전송용 리사이즈 (비용 절감)
│   └── ai/
│       ├── base.py        # AIProvider 인터페이스 ★
│       ├── factory.py     # 프로바이더 선택 ★
│       ├── gemini.py      # Gemini 구현 (현재 사용)
│       ├── mock.py        # 키 없이 개발용
│       └── prompts.py     # 모든 프롬프트 (PRD 10장)
├── requirements.txt
└── .env.example
```

## 핵심 API 플로우 (PRD 18장 MVP 사용자 플로우)

```
1. POST /auth/signup                → 토큰 발급
2. POST /photos/upload              → 사진 1~5장 업로드 (multipart)
3. POST /records                    → 오늘의 기록 생성 {photo_ids, main_photo_id}
4. POST /records/{id}/questions     → AI 질문 받기 (총 3회, {regenerate:true}로 다시 받기)
5. POST /records/{id}/answers       → 답변 저장 ({skipped:true}로 건너뛰기)
   (4↔5 반복 3회)
6. POST /records/{id}/film          → 필름 생성 (제목/내레이션/대표문장/키워드 + 과거기록 연결)
7. GET  /archive/calendar?year&month → 캘린더
8. GET  /records/{id}               → 기록 상세 / PATCH 수정 / DELETE 삭제
```

### 3차 기능 API

```
POST /moments                        낮 동안 순간 메모 남기기 → 밤 회고 첫 질문에 자동 반영
GET  /moments?date=YYYY-MM-DD        하루 순간 목록 / DELETE /moments/{id}
POST /voice/transcribe               음성 파일 업로드 → 텍스트 (클라이언트가 답변창에 채움)
POST /records (location 필드)        {name, latitude, longitude} → 날씨 자동 조회·저장
GET  /reports/monthly?year&month     월간 회고 리포트 (완성 필름 3개 이상 필요, 캐시됨)
GET  /reports/yearly?year            연간 필름 리포트 (&regenerate=true 로 재생성)
```

### 계정/설정/개인정보 API

```
PATCH /auth/me                       닉네임 수정
GET/PATCH /auth/me/settings          회상 켜기/끄기(recall_enabled), 리마인더 시각 저장
GET  /auth/me/export                 내 데이터 전체 내보내기 (개인정보 이동권)
PATCH /records/{id}                  {recall_blocked:true} — 이 기록 "다시 꺼내지 않기"
DELETE /auth/me                      계정과 모든 데이터 완전 삭제
```

### [FUTURE] 공유 링크 API (routers/share.py — 프론트 미연결, 확장 대비)

```
POST   /records/{id}/share           공유 토큰 발급 (완성 필름만)
DELETE /records/{id}/share           공유 회수
GET    /share/{token}                무인증 공개 조회 — 대화·키워드·위치 원천 제외
GET    /share/{token}/photo          대표 사진 공개 서빙
```

## 설계 결정 사항

- **하루 = 필름 1개**: `(user_id, date)` 유니크 제약. 자정 넘긴 새벽 회고는 클라이언트가 `date`를 어제로 보내면 됨.
- **Vision 은 별도 단계** (개발 PRD 6.1): 첫 질문 전에 대표 사진 맥락(scene/objects/mood)을 추출해 `photos.ai_context` 에 저장. 질문 모델에는 원본 이미지 대신 맥락 텍스트만 전달 — 비용 절감 + 재사용. 맥락은 사용자에게 절대 비노출.
- **quote 는 서버가 원문 검증** (개발 PRD 원칙 #4): LLM 이 지어낸 문장이면 답변 원문 문장으로 대체. PATCH 로 교체할 때도 답변 원문만 허용.
- **답변 0개 finalize 허용** (개발 PRD 6.3): 중립 제목만 생성하고 `in_progress` 유지 → 홈 "이어서 회고하기".
- **질문 생성 실패 시 질문 풀 폴백** (개발 PRD 7장): AI 장애가 회고를 멈추지 않는다.
- **질문 다시 받기 3회 제한**: 비용 가드레일 (`.env`에서 조정 가능).
- **기억 연결 2단 구조**: 1순위 임베딩 유사도(임계값 `.env`의 `RECALL_THRESHOLD`, 기본 0.55), 2순위 키워드 겹침 폴백. 마지막 질문 차례에 연결점이 있으면 recall형 질문으로 대체(회고당 최대 1회), 사용자가 반응한 경우에만 결과물에 포함. SQLite 는 파이썬 코사인 계산, PostgreSQL 전환 시 `services/embeddings.py`만 pgvector 로 교체.
- **회상 통제권은 사용자에게**: 기록별 `recall_blocked`("다시 꺼내지 않기") + 전역 `recall_enabled` 설정.
- **대화 원문은 앱 레벨 암호화** (개발 PRD 8장): 질문/답변/순간기록을 Fernet 으로 암호화 저장 (`ENCRYPTION_KEY`, 운영 모드 필수). 키워드는 검색용이라 제외.
- **EXIF 는 서버 저장 전 제거** (개발 PRD 8장): 업로드 시 재인코딩(GPS 등 메타데이터 제거 + 2048px 리사이즈).
- **위기 표현 안내** (서비스 PRD 17장): 답변에서 위기 표현 감지 시 응답에 `safety_notice`(전문 도움 정보)만 싣는다. 감지 결과는 저장·라벨링하지 않음.
- **리포트는 캐시**: 같은 기간 재요청 시 LLM 재호출 없음. `regenerate=true`로만 갱신.
- **날씨는 fail-soft**: Open-Meteo 조회 실패가 회고 플로우를 절대 막지 않음.
- **STT 결과는 바로 저장하지 않음**: 전사 텍스트를 반환만 하고, 사용자가 확인·수정 후 답변으로 제출.

## 운영(프로덕션) 기능 — v1.0 에서 적용됨

- **인증된 사진 서빙**: `/uploads` 정적 서빙 제거 → `GET /photos/{id}/file` (소유자만, 401/404). 클라이언트는 이미지 요청에 `Authorization` 헤더 필요.
- **Rate limit**: LLM 엔드포인트(질문/필름/전사) 사용자당 시간당 60회, 인증(가입/로그인) IP당 20회. `.env`로 조정. 다중 워커 배포 시 Redis 기반으로 교체 (`app/rate_limit.py` 주석 참고).
- **LLM 복원력**: 30초 타임아웃 + 지수 백오프 재시도 2회, JSON 파싱 실패 시 1회 재요청, 최종 실패는 502 + 친절한 안내 문구.
- **운영 모드 검증**: `APP_ENV=production` 이면 기본 JWT_SECRET/CORS `*` 로는 기동 자체가 거부됨. `/docs` 도 비공개.
- **요청 로깅 + X-Request-Id**, 전역 예외 핸들러(내부 정보 비노출), 헬스체크에 DB ping 포함.
- **계정 삭제 완전 정리**: 사진 실파일 + 순간 기록/임베딩/리포트/공유 링크/설정까지 삭제.
- **입력 가드**: 답변 2,000자 제한(422), 업로드는 재인코딩 통과분만 저장(디코딩 불가 시 400).

## 테스트

```bash
cd backend
.venv/bin/python -m pytest tests/ -q   # 38개 테스트 (mock AI, 임시 DB)
# test_api.py            기본 플로우/보안/아카이브
# test_crypto.py         대화 암호화 (암호문 저장·평문 전환기 호환)
# test_prd_alignment.py  EXIF 제거·quote 검증·답변 0개·Vision 맥락·질문 폴백
# test_final_stage.py    recall 질문 대체·회상 차단·위기 안내·설정·내보내기·공유
```

## 배포

```bash
# Docker (PostgreSQL 포함)
JWT_SECRET=$(openssl rand -hex 32) APP_ENV=production \
CORS_ORIGINS=https://yourdomain.app GEMINI_API_KEY=... \
docker compose up --build -d
```

## [FUTURE] 미리 만들어 둔 확장 모듈

파일 상단에 `[FUTURE ...]` 마커 주석이 있는 코드는 현재 PRD 범위 밖이지만
서비스 확장 시 바로 연결할 수 있도록 선구현·테스트해 둔 것이다.

- `routers/share.py` — 필름 웹 공유 링크 (카톡 미리보기/스토리 링크 도입 시 프론트 연결)
- `services/notifications.py` — 저녁 회고 리마인더 발송 (FCM/APNs + 스케줄러 연결 절차는 파일 주석 참고)
- `user_settings.reminder_time` — 리마인더 시각 저장 (발송 인프라 도입 전까지 저장만)

## 남은 운영 TODO

- [ ] `create_all` + 경량 마이그레이션(`database.run_light_migrations`) → Alembic 전환 (PostgreSQL 운영 시 필수)
- [ ] 사진 저장 로컬 디스크 → S3/Supabase Storage (다중 인스턴스 시 필수)
- [ ] rate limiter Redis 전환 (다중 워커/인스턴스 시)
- [ ] HEIC 업로드 지원 시 `pillow-heif` 설치 (현재는 디코딩 불가 형식 400 처리)
- [ ] 위기 표현 감지 패턴 고도화 (현재 보수적 키워드 — 오탐 방지 우선)
- [ ] Sentry 등 에러 트래킹 연동
