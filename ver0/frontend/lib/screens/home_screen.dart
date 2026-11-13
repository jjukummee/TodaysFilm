// 홈 — demo_design home-screen.tsx 대응.
// 상단 바(FilmMark + 날짜 / 테마 토글) → 인사 헤드라인 → 메인 CTA 카드(스프로킷 모티프)
// → 최근 필름 가로 캐러셀(사진 중심 카드).
//
// 백엔드 연동: 로그인 상태면 아카이브 캘린더 API로 실제 필름을 불러오고,
// 데모 모드(비로그인)에서만 demo_data 로 동작한다.
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/demo_data.dart';
import 'photo_select_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onGoArchive;
  const HomeScreen({super.key, this.onGoArchive});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeFilm {
  final String no, date, title, caption, imageUrl;
  const _HomeFilm(this.no, this.date, this.title, this.caption, this.imageUrl);
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService.instance;
  List<_HomeFilm> _films = [];
  bool _hasToday = false; // 오늘 필름이 이미 있는지
  bool _loading = false;
  String? _error;

  bool get _demo => !_api.isLoggedIn;

  @override
  void initState() {
    super.initState();
    if (_demo) {
      _films = [
        for (final f in demoFilms)
          _HomeFilm(f.no, f.date, f.title, f.caption, f.imageUrl),
      ];
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 이번 달 + 지난 달 기록을 모아 최근 필름 캐러셀 구성
      final now = DateTime.now();
      final prev = DateTime(now.year, now.month - 1);
      final results = await Future.wait([
        _api.monthCalendar(now.year, now.month),
        _api.monthCalendar(prev.year, prev.month),
      ]);
      final days = [
        ...(results[0]['days'] as List),
        ...(results[1]['days'] as List),
      ].cast<Map<String, dynamic>>();
      days.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final films = <_HomeFilm>[];
      for (var i = 0; i < days.length; i++) {
        final d = days[i];
        if (d['film_title'] == null || d['main_photo_url'] == null) continue;
        final date = DateTime.parse(d['date']);
        films.add(_HomeFilm(
          '${days.length - i}'.padLeft(3, '0'),
          '${date.month}월 ${date.day}일',
          d['film_title'],
          d['representative_sentence'] ?? '',
          ApiService.resolveUrl(d['main_photo_url']),
        ));
      }
      setState(() {
        _films = films;
        _hasToday = days.any((d) => d['date'] == todayStr);
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = '서버에 연결할 수 없어요.\n백엔드 실행 후 아래로 당겨 새로고침해 주세요.';
      });
    }
  }

  String _todayLabel() {
    final now = DateTime.now();
    const weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    return '${now.month}월 ${now.day}일 ${weekdays[now.weekday - 1]}';
  }

  void _startRecord() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PhotoSelectScreen()))
        .then((_) {
      if (!_demo) _load(); // 필름 생성 플로우에서 돌아오면 새로고침
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: Brand.amber,
        onRefresh: () async {
          if (!_demo) await _load();
        },
        child: ListView(
          // extendBody: 유리 탭바에 가리지 않도록 하단 여백 확보
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // ─── 상단 바: 브랜드 마크 + 날짜 / 테마 토글 ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(children: [
                const FilmMark(size: 22),
                const SizedBox(width: 8),
                Text(_todayLabel(),
                    style: FilmText.title(context, size: 15)),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => themeModeNotifier.value =
                      isDark ? ThemeMode.light : ThemeMode.dark,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      size: 22,
                      color: c.sub,
                    ),
                  ),
                ),
              ]),
            ),

            // ─── 인사 헤드라인 ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_hasToday ? '오늘의 필름이\n완성됐어요' : '오늘 하루, 돌아볼까요?',
                      style: FilmText.display(context, size: 26)),
                  const SizedBox(height: 8),
                  Text(
                      _hasToday
                          ? '아카이브에서 오늘의 기록을 다시 볼 수 있어요.'
                          : '아무 일 없던 하루에도 장면은 있어요.',
                      style: FilmText.caption(context, size: 14)),
                ],
              ),
            ),

            // ─── 메인 CTA 카드 ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: c.card(),
                child: Stack(children: [
                  // 좌우 스프로킷 모티프
                  Positioned(
                      top: 0, bottom: 0, left: 4, child: _SprocketColumn(c: c)),
                  Positioned(
                      top: 0, bottom: 0, right: 4, child: _SprocketColumn(c: c)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
                    child: Column(children: [
                      const FilmMark(size: 40),
                      const SizedBox(height: 16),
                      Text(
                        _hasToday
                            ? '오늘의 장면이 필름으로 남았어요'
                            : '오늘의 필름은 아직 비어 있어요',
                        style: FilmText.body(context,
                            size: 15, weight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _hasToday
                            ? '내일 저녁, 또 다른 장면으로 만나요.'
                            : '사진 한 장으로 오늘을 현상해 보세요.',
                        style: FilmText.caption(context, size: 13),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: PrimaryButton(
                          label: _hasToday ? '오늘의 필름 보러가기' : '오늘의 필름 만들기',
                          onPressed:
                              _hasToday ? widget.onGoArchive : _startRecord,
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),

            // ─── 최근 필름 섹션 ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('최근 필름', style: FilmText.title(context, size: 17)),
                  GestureDetector(
                    onTap: widget.onGoArchive,
                    behavior: HitTestBehavior.opaque,
                    child: Text('전체보기',
                        style: FilmText.caption(context,
                            size: 13, weight: FontWeight.w500)),
                  ),
                ],
              ),
            ),

            // 가로 캐러셀 (사진 중심 카드)
            SizedBox(
              height: 296,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Brand.amber, strokeWidth: 2))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: FilmText.caption(context,
                                  size: 13, height: 1.6)))
                      : _films.isEmpty
                          ? Center(
                              child: Text('아직 완성된 필름이 없어요.\n첫 필름을 만들어보세요.',
                                  textAlign: TextAlign.center,
                                  style: FilmText.caption(context,
                                      size: 13, height: 1.6)))
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: kPageHPad,
                              physics: const BouncingScrollPhysics(),
                              itemCount:
                                  _films.length > 6 ? 6 : _films.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, i) => _RecentFilmCard(
                                film: _films[i],
                                onTap: widget.onGoArchive,
                              ),
                            ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

/// CTA 카드 좌우의 필름 스프로킷 점 열
class _SprocketColumn extends StatelessWidget {
  final FilmColors c;
  const _SprocketColumn({required this.c});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          8,
          (_) => Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// 최근 필름 카드 — 172px 폭, 224px 사진 + 하단 날짜/문장
class _RecentFilmCard extends StatelessWidget {
  final _HomeFilm film;
  final VoidCallback? onTap;
  const _RecentFilmCard({required this.film, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 172,
        clipBehavior: Clip.antiAlias,
        decoration: c.card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 사진 + 세리프 제목 오버레이
          SizedBox(
            height: 210,
            width: double.infinity,
            child: Stack(fit: StackFit.expand, children: [
              Image.network(
                film.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: c.surface),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: [0, 0.55],
                    colors: [Color(0x8C000000), Color(0x00000000)],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  film.title.replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FilmText.serif(context,
                      size: 16, color: Colors.white, height: 1.35),
                ),
              ),
            ]),
          ),
          // 날짜 + 대표 문장
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(film.date,
                    style: FilmText.caption(context,
                        size: 11, weight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  film.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FilmText.body(context, size: 12.5, height: 1.5),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
