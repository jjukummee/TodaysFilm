// 현상 중 → 결과 — demo_design DevelopingScreen + ResultScreen 대응.
// 로딩: 맥동하는 FilmMark + 진행 바 / 결과: TODAY'S FILM 카드(사진 + 세리프 제목
// + 대표 문장 + 내레이션 + 키워드) + 홈/아카이브 이동 버튼.
//
// 필름 카드는 RepaintBoundary 로 감싸져 있어 PNG 캡처(공유/저장)가 가능하다.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/demo_data.dart';

class FilmResultScreen extends StatefulWidget {
  final String? recordId;
  final List<Uint8List?> photoBytes;
  final List<String?> demoUrls;
  const FilmResultScreen({
    super.key,
    required this.recordId,
    required this.photoBytes,
    required this.demoUrls,
  });

  @override
  State<FilmResultScreen> createState() => _FilmResultScreenState();
}

class _FilmResultScreenState extends State<FilmResultScreen>
    with SingleTickerProviderStateMixin {
  final _cardKey = GlobalKey(); // RepaintBoundary 캡처용
  Map<String, dynamic>? _film;
  int _loadingMsgIndex = 0;
  Timer? _timer;
  late final AnimationController _pulse;

  static const _loadingMessages = [
    '오늘을 현상하고 있어요',
    '당신의 답변을 필름처럼 엮는 중이에요',
    '오늘 하루에 제목을 붙이는 중이에요',
  ];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _film == null) {
        setState(() =>
            _loadingMsgIndex = (_loadingMsgIndex + 1) % _loadingMessages.length);
      }
    });
    _generate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (widget.recordId == null) {
      // 데모 모드: 현상 연출 후 샘플 결과
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _film = Map.of(demoFilmResult));
      return;
    }
    try {
      final film = await ApiService.instance.generateFilm(widget.recordId!);
      if (mounted) setState(() => _film = film);
    } on ApiException catch (e) {
      if (mounted) {
        showFilmSnack(context, e.message);
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        showFilmSnack(context, '서버에 연결할 수 없어요.');
        Navigator.of(context).pop();
      }
    }
  }

  // 필름은 생성 시점에 이미 아카이브에 저장돼 있다 → 여기선 탐색만 한다.
  void _goHome() {
    rootTabNotifier.value = 0;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _goArchive() {
    rootTabNotifier.value = 1; // 아카이브 탭
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _film == null ? _buildLoading(context) : _buildResult(context),
        ),
      ),
    );
  }

  // ─── 현상 중 (로딩) ───
  Widget _buildLoading(BuildContext context) {
    final c = FilmColors.of(context);
    return Center(
      key: const ValueKey('loading'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.4, end: 1.0).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
              child: const FilmMark(size: 64),
            ),
          ),
          const SizedBox(height: 32),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              _loadingMessages[_loadingMsgIndex],
              key: ValueKey(_loadingMsgIndex),
              style: FilmText.title(context, size: 19),
            ),
          ),
          const SizedBox(height: 8),
          Text('잠시만 기다려 주세요.',
              style: FilmText.caption(context, size: 14)),
          const SizedBox(height: 28),
          // 진행 바
          SizedBox(
            width: 160,
            height: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                backgroundColor: c.surface,
                color: Brand.amber,
                minHeight: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 결과 ───
  Widget _buildResult(BuildContext context) {
    final c = FilmColors.of(context);
    final film = _film!;
    final now = DateTime.now();
    const weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    final dateLabel =
        '${now.month}월 ${now.day}일 ${weekdays[now.weekday - 1]}';
    final keywords = (film['keywords'] as List?)?.cast<String>() ?? [];

    return Column(key: const ValueKey('result'), children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          children: [
            Text("TODAY'S FILM",
                textAlign: TextAlign.center,
                style: FilmText.overline(context)),
            const SizedBox(height: 16),

            // ── 필름 카드 (캡처 가능) ──
            RepaintBoundary(
              key: _cardKey,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: c.card(),
                child: Column(children: [
                  // 대표 사진 + 세리프 제목 오버레이
                  SizedBox(
                    height: 300,
                    width: double.infinity,
                    child: Stack(fit: StackFit.expand, children: [
                      widget.photoBytes.isNotEmpty &&
                              widget.photoBytes.first != null
                          ? Image.memory(widget.photoBytes.first!,
                              fit: BoxFit.cover)
                          : Image.network(
                              widget.demoUrls.isNotEmpty &&
                                      widget.demoUrls.first != null
                                  ? widget.demoUrls.first!
                                  : demoFilms.first.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: c.surface)),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            stops: [0, 0.6],
                            colors: [Color(0x99000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dateLabel,
                                style: FilmText.caption(context,
                                    size: 12,
                                    weight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.8))),
                            const SizedBox(height: 4),
                            Text(
                              (film['film_title'] ?? '')
                                  .toString()
                                  .replaceAll('\n', ' '),
                              style: FilmText.serif(context,
                                  size: 24,
                                  color: Colors.white,
                                  height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ),

                  // 대표 문장 + 내레이션 + 키워드
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '"${film['representative_sentence'] ?? ''}"',
                          style: FilmText.body(context, size: 15, height: 1.6),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Container(height: 1, color: c.border),
                        ),
                        Text(
                          film['ending_narration'] ?? '',
                          style: FilmText.caption(context,
                              size: 13.5, height: 1.7),
                        ),
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
                                      style: FilmText.caption(context,
                                          size: 12, height: 1.3)),
                                ),
                            ],
                          ),
                        ],
                        // 기억 연결 문장 (있을 때만)
                        if (film['memory_link'] != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Brand.amber.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(Radii.input),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.auto_awesome,
                                    size: 14, color: Brand.amberTo),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    film['memory_link']['link_sentence'] ?? '',
                                    style: FilmText.body(context,
                                        size: 12.5, height: 1.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),

      // ─── 하단 액션 ───
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(label: '홈으로', onPressed: _goHome),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(label: '아카이브로 이동', onPressed: _goArchive),
          ),
        ]),
      ),
    ]);
  }
}
