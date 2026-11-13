// 아카이브 — demo_design archive-screen.tsx / archive-graph-screen.tsx 대응.
// 헤더 → 세그먼트(캘린더/그래프) → 캘린더: 사진 캘린더 + 프리뷰 + 상세 시트
//                              → 그래프: 키워드·필름 지식 그래프.
//
// 백엔드 연동: 로그인 상태면 GET /archive/calendar 로 실제 데이터,
// 데모 모드(비로그인)에서만 demo_data 로 동작한다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api_service.dart';
import '../services/demo_data.dart';
import 'archive_graph_view.dart';

class _ArchiveFilm {
  final String? recordId; // 데모 모드에서는 null
  final String no, title, caption, imageUrl;
  final int day;
  const _ArchiveFilm({
    this.recordId,
    required this.no,
    required this.day,
    required this.title,
    required this.caption,
    required this.imageUrl,
  });
}

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final _api = ApiService.instance;
  bool _calendarView = true;
  int? _selectedDay;
  late DateTime _month;

  Map<int, _ArchiveFilm> _films = {};
  bool _loading = false;

  // 그래프 뷰용 키워드 (day → keywords). 그래프 탭 진입 시 lazy 로드.
  final Map<int, List<String>> _dayKeywords = {};
  bool _graphKeywordsLoaded = false;
  bool _graphLoading = false;

  bool get _demo => !_api.isLoggedIn;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    if (_demo) {
      _films = {
        for (final f in demoFilms)
          f.day: _ArchiveFilm(
              no: f.no,
              day: f.day,
              title: f.title,
              caption: f.caption,
              imageUrl: f.imageUrl),
      };
      _selectedDay = demoFilms.first.day;
      for (final f in demoFilms) {
        _dayKeywords[f.day] = f.keywords;
      }
      _graphKeywordsLoaded = true;
    } else {
      _load();
    }
  }

  /// 그래프 뷰용 키워드 lazy 로드 — 최근 필름 최대 5편의 상세를 조회.
  Future<void> _loadGraphKeywords() async {
    if (_demo || _graphKeywordsLoaded || _graphLoading) return;
    final targets = (_films.values.toList()
          ..sort((a, b) => b.day.compareTo(a.day)))
        .where((f) => f.recordId != null)
        .take(5)
        .toList();
    if (targets.isEmpty) {
      _graphKeywordsLoaded = true;
      return;
    }
    setState(() => _graphLoading = true);
    try {
      final details = await Future.wait(
          [for (final f in targets) _api.recordDetail(f.recordId!)]);
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < targets.length; i++) {
          _dayKeywords[targets[i].day] =
              (details[i]['keywords'] as List?)?.cast<String>() ?? const [];
        }
        _graphKeywordsLoaded = true;
        _graphLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _graphLoading = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _api.monthCalendar(_month.year, _month.month);
      final days = (result['days'] as List).cast<Map<String, dynamic>>();

      final films = <int, _ArchiveFilm>{};
      for (var i = 0; i < days.length; i++) {
        final d = days[i];
        if (d['main_photo_url'] == null) continue;
        final day = DateTime.parse(d['date']).day;
        films[day] = _ArchiveFilm(
          recordId: d['record_id'],
          no: '${i + 1}'.padLeft(3, '0'),
          day: day,
          title: d['film_title'] ?? '(작성 중)',
          caption: d['representative_sentence'] ?? '',
          imageUrl: ApiService.resolveUrl(d['main_photo_url']),
        );
      }
      if (!mounted) return;
      setState(() {
        _films = films;
        _loading = false;
        if (_selectedDay == null && films.isNotEmpty) {
          _selectedDay = films.keys.reduce((a, b) => a > b ? a : b);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _films = {};
        _loading = false;
      });
      showFilmSnack(context, '서버에 연결할 수 없어요.');
    }
  }

  void _changeMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDay = null;
      if (_demo) return;
      _films = {};
      _dayKeywords.clear();
      _graphKeywordsLoaded = false;
    });
    if (!_demo) _load();
  }

  // ─── 기록 상세 바텀시트 (실제 DB 데이터) ───
  Future<void> _openDetail(_ArchiveFilm film) async {
    if (film.recordId == null) {
      showFilmSnack(context, '데모 모드에서는 상세 보기를 지원하지 않아요.');
      return;
    }
    Map<String, dynamic> detail;
    try {
      detail = await _api.recordDetail(film.recordId!);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final c = FilmColors.of(context);
    final keywords = (detail['keywords'] as List?)?.cast<String>() ?? [];
    showModalBottomSheet(
      context: context,
      backgroundColor: c.elevated,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.66,
        maxChildSize: 0.92,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: c.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            // 사진 + 세리프 제목 오버레이
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card),
              child: SizedBox(
                height: 260,
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(film.imageUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: c.surface)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: [0, 0.6],
                        colors: [Color(0x8C000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_month.month}월 ${film.day}일'
                          '${detail['weather_summary'] != null ? ' · ${detail['weather_summary']}' : ''}',
                          style: FilmText.caption(context,
                              size: 12,
                              weight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.8)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (detail['film_title'] ?? '(작성 중)')
                              .toString()
                              .replaceAll('\n', ' '),
                          style: FilmText.serif(context,
                              size: 22, color: Colors.white, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            if (detail['representative_sentence'] != null) ...[
              Text('"${detail['representative_sentence']}"',
                  style: FilmText.body(context, size: 16, height: 1.6)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(height: 1, color: c.border),
              ),
            ],
            if (detail['ending_narration'] != null)
              Text(detail['ending_narration'],
                  style: FilmText.caption(context, size: 14, height: 1.8)),
            if (keywords.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in keywords)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text('# $k',
                          style:
                              FilmText.caption(context, size: 12, height: 1.3)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    final films = _films;
    final selectedFilm = _selectedDay != null ? films[_selectedDay] : null;
    final recentFilms = films.values.toList()
      ..sort((a, b) => b.day.compareTo(a.day));

    return SafeArea(
      bottom: false,
      child: Column(children: [
        // ─── 헤더 ───
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            Text('아카이브', style: FilmText.display(context, size: 22)),
            const Spacer(),
          ]),
        ),

        // ─── 세그먼트 (캘린더 / 그래프) ───
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.input),
            ),
            child: Row(children: [
              _segmentButton('캘린더', true),
              _segmentButton('그래프', false),
            ]),
          ),
        ),

        // ─── 콘텐츠 ───
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Brand.amber, strokeWidth: 2))
              : _calendarView
                  ? ListView(
                      // extendBody: 유리 탭바에 가리지 않도록 하단 여백 확보
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).padding.bottom),
                      children: [
                        _monthNav(context),
                        _weekdayLabels(context),
                        _calendarGrid(context, films),
                        if (selectedFilm != null)
                          _filmPreview(context, selectedFilm),
                        const SizedBox(height: 24),
                      ],
                    )
                  : ArchiveGraphView(
                      loading: _graphLoading,
                      films: [
                        for (final f in recentFilms)
                          ArchiveGraphFilm(
                            day: f.day,
                            title: f.title,
                            caption: f.caption,
                            imageUrl: f.imageUrl,
                            keywords: _dayKeywords[f.day] ?? const [],
                          ),
                      ],
                      onOpenFilm: (gf) {
                        final f = films[gf.day];
                        if (f != null) _openDetail(f);
                      },
                    ),
        ),
      ]),
    );
  }

  Widget _segmentButton(String label, bool calendar) {
    final c = FilmColors.of(context);
    final active = _calendarView == calendar;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _calendarView = calendar);
          if (!calendar) _loadGraphKeywords(); // 그래프 탭 진입 시 키워드 로드
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.bg : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? const [
                    BoxShadow(
                        color: Color(0x14191919),
                        blurRadius: 3,
                        offset: Offset(0, 1)),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: FilmText.title(context,
                size: 14, color: active ? Brand.amberTo : c.sub),
          ),
        ),
      ),
    );
  }

  Widget _monthNav(BuildContext context) {
    final c = FilmColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _changeMonth(-1),
            child: SizedBox(
              width: 40,
              height: 32,
              child: Icon(Icons.chevron_left, size: 22, color: c.sub),
            ),
          ),
          Text('${_month.year}년 ${_month.month}월',
              style: FilmText.title(context, size: 18)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _changeMonth(1),
            child: SizedBox(
              width: 40,
              height: 32,
              child: Icon(Icons.chevron_right, size: 22, color: c.sub),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text('이번 달 필름 ${_films.length}편',
            style: FilmText.caption(context, size: 12)),
      ]),
    );
  }

  Widget _weekdayLabels(BuildContext context) {
    final c = FilmColors.of(context);
    const labels = ['일', '월', '화', '수', '목', '금', '토'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: List.generate(7, (i) {
          return Expanded(
            child: Center(
              child: Text(labels[i],
                  style: FilmText.caption(context,
                      size: 11,
                      weight: FontWeight.w500,
                      color: i == 0 ? const Color(0xFFD0705A) : c.sub)),
            ),
          );
        }),
      ),
    );
  }

  Widget _calendarGrid(BuildContext context, Map<int, _ArchiveFilm> films) {
    final c = FilmColors.of(context);
    final now = DateTime.now();
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <int?>[
      ...List.filled(firstWeekday, null),
      ...List.generate(daysInMonth, (i) => i + 1),
    ];

    final isCurrentMonth =
        _month.year == now.year && _month.month == now.month;
    // 데모 모드 데이터는 현재 달에만 표시
    final showFilms = !_demo || isCurrentMonth;

    return Padding(
      padding: kPageHPad,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: cells.length,
        itemBuilder: (context, i) {
          final day = cells[i];
          if (day == null) return const SizedBox();
          final film = showFilms ? films[day] : null;
          final isSelected = _selectedDay == day;
          final isToday = isCurrentMonth && day == now.day;

          // 오늘 = 앰버 인셋 링 / 선택 = 굵은 링
          final ring = isSelected
              ? Border.all(color: Brand.amber, width: 2)
              : isToday
                  ? Border.all(color: Brand.amber, width: 1.5)
                  : null;

          if (film != null) {
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedDay = day);
              },
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(film.imageUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: c.surface)),
                  Container(color: Colors.black.withOpacity(0.25)),
                  Positioned(
                    top: 3,
                    right: 5,
                    child: Text('$day',
                        style: FilmText.caption(context,
                            size: 11,
                            weight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.3)),
                  ),
                  if (ring != null)
                    Container(
                      decoration: BoxDecoration(
                        border: ring,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ]),
              ),
            );
          }

          return Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(8),
              border: ring,
            ),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 3, right: 5),
                child: Text('$day',
                    style: FilmText.caption(context,
                        size: 11,
                        weight: FontWeight.w500,
                        color: isToday ? Brand.amberTo : c.sub,
                        height: 1.3)),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 선택한 날의 필름 프리뷰 카드 (탭 → 상세 시트)
  Widget _filmPreview(BuildContext context, _ArchiveFilm film) {
    final c = FilmColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: PressableScale(
        onTap: () => _openDetail(film),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: c.card(radius: Radii.group),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.input),
              child: Image.network(film.imageUrl,
                  width: 52, height: 52, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      width: 52, height: 52, color: c.surface)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(film.title.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FilmText.title(context, size: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '${_month.month}월 ${film.day}일 · ${film.caption}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FilmText.caption(context, size: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: c.sub),
          ]),
        ),
      ),
    );
  }

}
