# 오늘의 필름 — 프론트엔드 (Flutter)

피그마 "오늘의 필름 홈 화면 디자인"(Figma Make)을 Flutter로 구현한 앱.

## 실행

```bash
cd frontend
flutter pub get
flutter run          # 시뮬레이터/실기기
```

백엔드 연동 시 `lib/services/api_service.dart` 의 `baseUrl` 확인:
- iOS 시뮬레이터: `http://localhost:8000`
- Android 에뮬레이터: `http://10.0.2.2:8000`
- 실기기: PC의 LAN IP

**서버 없이도 실행됨** — 로그인 전에는 모든 화면이 데모 데이터(피그마 디자인의 샘플 이미지)로 동작해서 디자이너도 바로 UI를 확인할 수 있다.

## 구현 화면

| 화면 | 출처 | 파일 |
|---|---|---|
| 홈 (히어로 + 스프로킷 CTA + 지난 필름 캐러셀) | 피그마 | `screens/home_screen.dart` |
| STEP 01 사진 선택 (필름 슬롯 + 그리드) | 피그마 | `screens/photo_select_screen.dart` |
| 아카이브 (사진 캘린더 ↔ 그리드 토글) | 피그마 | `screens/archive_screen.dart` |
| 마이 (프로필 + 통계 + 설정) | 피그마 | `screens/my_screen.dart` |
| STEP 02 감독의 질문 | **추가 설계** | `screens/question_screen.dart` |
| STEP 03 생성 로딩 + 필름 카드 결과 | **추가 설계** | `screens/film_result_screen.dart` |

STEP 02/03은 피그마에 없지만 회고 플로우에 필수라 같은 디자인 언어(세리프 헤드라인, 스프로킷, 오렌지 필 버튼, STEP 라벨)로 설계해 추가했다.

## 디자인 시스템 (`lib/core/`)

- **컬러**: 피그마 토큰 그대로 — 필름 오렌지 `#E8703A`, 크림 배경 `#F7F4EF`, 다크 `#1A1A1A`. 라이트/다크 모두 지원 (`FilmColors`).
- **타이포**: Gowun Batang(감성 세리프 헤드라인) / IBM Plex Sans KR(본문) / Instrument Serif 이탤릭(No.004, 날짜 등 영문 악센트). google_fonts 런타임 로드.
- **모티프**: 스프로킷 스트립, 세피아 톤 필름 카드, 점선 empty 슬롯, 오버라인 라벨.

### 디자인에서 과감하게 손본 것 (트렌드 반영)

1. **햅틱 피드백** — 사진 선택/탭 전환/CTA에 미세 진동. 요즘 앱의 "쫀득함"은 여기서 나온다.
2. **마이크로 애니메이션** — 선택 시 scale 축소, 질문 전환 AnimatedSwitcher, 탭 인디케이터 애니메이션.
3. **iOS 바운스 스크롤** — 캐러셀에 BouncingScrollPhysics.
4. **생성 로딩 감성 문구 순환** — "당신의 답변을 필름처럼 엮는 중이에요" 2초 간격 전환 (PRD 8.5).
5. **iOS 사진 제한 접근 배너** — 디자인의 "일부 사진만 허용됨" 배너를 실제 `PhotoManager.presentLimited()` 와 연결.
6. 디자인의 상태바/다이나믹 아일랜드/폰 프레임은 웹 목업용이므로 제거 — 실제 앱에서는 OS가 그린다.

**폰트 제안**: 본문을 Pretendard로 바꾸면 더 트렌디하다(토스·당근 등 표준). Google Fonts에 없어서 직접 번들 필요 — `assets/fonts/`에 넣고 pubspec 등록 후 `theme.dart`의 `ibmPlexSansKr` 부분만 교체하면 된다.

## 백엔드 연동 (`lib/services/api_service.dart`)

회고 플로우는 로그인 상태면 실제 API를 탄다:
사진 업로드 → 기록 생성 → 질문 3회(다시 받기/건너뛰기 포함) → 필름 생성(기억 연결 문장 표시까지).

TODO (다음 단계):
- [ ] 로그인/회원가입 화면 (ApiService에 메서드는 준비됨)
- [ ] 아카이브를 `monthCalendar()` API로 교체 (현재 데모 데이터)
- [ ] 필름 카드 공유 — `RepaintBoundary`(_cardKey) → PNG 캡처 → share_plus
- [ ] iOS `Info.plist`에 `NSPhotoLibraryUsageDescription`, Android `READ_MEDIA_IMAGES` 권한 추가
