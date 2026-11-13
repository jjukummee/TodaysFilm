// 아카이브 · 그래프 뷰 — demo_design archive-graph-screen.tsx 대응.
// 옵시디언 그래프 뷰처럼 키워드(라벨)·필름(사진)·장식(점) 노드가 흩어져 있고,
// 연관된 노드끼리 곡선 엣지로 연결된 지식 그래프. 정적 배치 — 물리 시뮬레이션 없음.
//
// 실제 데이터(필름 + 키워드)로 노드를 구성하고, 키워드↔필름 연결을 엣지로 그린다.
// 노드 탭: 라벨 = 선택(연결 하이라이트) / 사진 = 미니 정보 시트 → 기록 열기.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/widgets.dart';

/// 그래프에 올릴 필름 한 편
class ArchiveGraphFilm {
  final int day;
  final String title;
  final String caption;
  final String imageUrl;
  final List<String> keywords;
  const ArchiveGraphFilm({
    required this.day,
    required this.title,
    required this.caption,
    required this.imageUrl,
    required this.keywords,
  });
}

/// 그래프 전용 캔버스 컬러 (theme.css --film-canvas / --film-node / --film-edge)
class _GraphColors {
  final Color canvas, node, nodeText, edge;
  const _GraphColors({
    required this.canvas,
    required this.node,
    required this.nodeText,
    required this.edge,
  });

  static const light = _GraphColors(
    canvas: Color(0xFFF2F0EB),
    node: Color(0x298B8680), // rgba(139,134,128,0.16)
    nodeText: Color(0xFF8B8680),
    edge: Color(0x618B8680), // rgba(139,134,128,0.38)
  );
  static const dark = _GraphColors(
    canvas: Color(0xFF0F1014),
    node: Color(0x14F2EFE9), // rgba(242,239,233,0.08)
    nodeText: Color(0xFFB8B2A9),
    edge: Color(0x24F2EFE9), // rgba(242,239,233,0.14)
  );

  static _GraphColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

// ─── 정적 배치 템플릿 (353×452 기준 — tsx 원본 좌표) ───

const double _kCanvasW = 353;
const double _kCanvasH = 452;

class _Slot {
  final double x, y, r;
  const _Slot(this.x, this.y, this.r);
}

const _labelSlots = [
  _Slot(108, 128, 32),
  _Slot(250, 168, 29),
  _Slot(268, 312, 25),
  _Slot(118, 300, 22),
  _Slot(56, 214, 20),
];

const _photoSlots = [
  _Slot(168, 66, 22),
  _Slot(312, 108, 19),
  _Slot(196, 236, 18),
  _Slot(178, 388, 17),
  _Slot(60, 132, 16),
];

const _dotSlots = [
  _Slot(214, 118, 7),
  _Slot(322, 232, 9),
  _Slot(300, 380, 8),
  _Slot(96, 388, 7),
  _Slot(150, 176, 10),
  _Slot(40, 300, 6),
];

enum _NodeKind { label, photo, dot }

double _slotDist(_Slot a, _Slot b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

class _Node {
  final String id;
  final _Slot slot;
  final _NodeKind kind;
  final String? label; // 키워드
  final int count; // 키워드 등장 횟수
  final ArchiveGraphFilm? film; // 사진 노드
  const _Node({
    required this.id,
    required this.slot,
    required this.kind,
    this.label,
    this.count = 0,
    this.film,
  });
}

class _Edge {
  final String a, b;
  final bool strong;
  const _Edge(this.a, this.b, {this.strong = false});
}

class ArchiveGraphView extends StatefulWidget {
  final List<ArchiveGraphFilm> films;
  final bool loading;
  final void Function(ArchiveGraphFilm film)? onOpenFilm;
  const ArchiveGraphView({
    super.key,
    required this.films,
    this.loading = false,
    this.onOpenFilm,
  });

  @override
  State<ArchiveGraphView> createState() => _ArchiveGraphViewState();
}

class _ArchiveGraphViewState extends State<ArchiveGraphView>
    with SingleTickerProviderStateMixin {
  String? _selected; // 선택된 노드 id

  List<_Node> _nodes = [];
  List<_Edge> _edges = [];
  List<(String, int)> _topKeywords = [];

  // 등장 애니메이션 — 노드가 순차 fade-in 되고 엣지가 그려지는 "성좌 완성" 연출
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _buildGraph();
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ArchiveGraphView old) {
    super.didUpdateWidget(old);
    if (_sig(old.films) != _sig(widget.films)) {
      _buildGraph();
      _entrance.forward(from: 0);
    }
  }

  static String _sig(List<ArchiveGraphFilm> films) =>
      films.map((f) => '${f.day}:${f.keywords.join(',')}').join('|');

  /// 필름/키워드 → 노드·엣지 구성
  void _buildGraph() {
    final films = widget.films.take(_photoSlots.length).toList();

    // 키워드 집계 (등장 횟수 내림차순)
    final counts = <String, int>{};
    for (final f in films) {
      for (final k in f.keywords) {
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final keywords = sorted.take(_labelSlots.length).toList();
    _topKeywords = [for (final e in keywords) (e.key, e.value)];

    final nodes = <_Node>[];
    final edges = <_Edge>[];
    final keywordId = <String, String>{};

    // 라벨 노드
    for (var i = 0; i < keywords.length; i++) {
      final id = 'k$i';
      keywordId[keywords[i].key] = id;
      nodes.add(_Node(
        id: id,
        slot: _labelSlots[i],
        kind: _NodeKind.label,
        label: keywords[i].key,
        count: keywords[i].value,
      ));
    }
    // 라벨 id → 슬롯 룩업 (배정·거리 계산용)
    final labelSlotById = <String, _Slot>{
      for (var i = 0; i < keywords.length; i++) 'k$i': _labelSlots[i],
    };

    // 사진 노드 — 연결 기반 greedy 슬롯 배정:
    // 주 키워드(첫 키워드) 슬롯에서 가장 가까운 빈 슬롯에 놓아 엣지를 짧게 만든다.
    // 짧은 엣지 = 교차 확률 급감.
    final freeSlots = List<int>.generate(_photoSlots.length, (i) => i);
    for (var i = 0; i < films.length; i++) {
      final anchorId = films[i].keywords.isNotEmpty
          ? keywordId[films[i].keywords.first]
          : null;
      final anchor = anchorId != null ? labelSlotById[anchorId] : null;
      int slotIndex;
      if (anchor == null) {
        slotIndex = freeSlots.removeAt(0);
      } else {
        freeSlots.sort((a, b) => _slotDist(_photoSlots[a], anchor)
            .compareTo(_slotDist(_photoSlots[b], anchor)));
        slotIndex = freeSlots.removeAt(0);
      }
      nodes.add(_Node(
        id: 'p$i',
        slot: _photoSlots[slotIndex],
        kind: _NodeKind.photo,
        film: films[i],
      ));
    }
    // 장식 점 노드
    for (var i = 0; i < _dotSlots.length; i++) {
      nodes.add(_Node(id: 'd$i', slot: _dotSlots[i], kind: _NodeKind.dot));
    }

    // 키워드 ↔ 필름 엣지 — 항목당 주 키워드 2개까지만 (엣지 과밀 방지)
    for (var i = 0; i < films.length; i++) {
      for (final k in films[i].keywords.take(2)) {
        final kid = keywordId[k];
        if (kid != null) edges.add(_Edge(kid, 'p$i', strong: true));
      }
    }
    // 키워드 ↔ 키워드 (같은 필름에 함께 등장) — 슬롯이 가까울 때만 그린다.
    // 멀리 떨어진 키워드 쌍의 엣지는 캔버스를 가로질러 교차의 주범이 된다.
    final seen = <String>{};
    for (final f in films) {
      final ids =
          f.keywords.map((k) => keywordId[k]).whereType<String>().toList();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final sa = labelSlotById[ids[i]]!;
          final sb = labelSlotById[ids[j]]!;
          if (_slotDist(sa, sb) > _kCanvasW * 0.6) continue;
          final key = '${ids[i]}-${ids[j]}';
          if (seen.add(key)) edges.add(_Edge(ids[i], ids[j]));
        }
      }
    }
    // 장식 점 → 가장 가까운 라벨/사진 하나에만 약한 엣지
    for (var i = 0; i < _dotSlots.length; i++) {
      _Node? nearest;
      var best = double.infinity;
      for (final n in nodes) {
        if (n.kind == _NodeKind.dot) continue;
        final d = _slotDist(_dotSlots[i], n.slot);
        if (d < best) {
          best = d;
          nearest = n;
        }
      }
      if (nearest != null) edges.add(_Edge('d$i', nearest.id));
    }

    _nodes = nodes;
    _edges = edges;
    // 기본 선택 = 가장 큰 키워드
    _selected = keywords.isNotEmpty ? 'k0' : null;
  }

  Set<String> get _connected {
    final sel = _selected;
    if (sel == null) return {};
    final set = <String>{sel};
    for (final e in _edges) {
      if (e.a == sel) set.add(e.b);
      if (e.b == sel) set.add(e.a);
    }
    return set;
  }

  void _tapLabel(_Node node) {
    HapticFeedback.selectionClick();
    setState(() => _selected = _selected == node.id ? null : node.id);
  }

  /// 사진 노드 탭 → 미니 정보 시트 (FilmInfoSheet)
  void _tapPhoto(_Node node) {
    HapticFeedback.selectionClick();
    final film = node.film!;
    final c = FilmColors.of(context);
    showFilmSheet(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(film.imageUrl,
                  width: 64, height: 64, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(width: 64, height: 64, color: c.surface)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${film.day}일'
                    '${film.keywords.isNotEmpty ? ' · ${film.keywords.first}' : ''}',
                    style: FilmText.caption(context,
                        size: 12, weight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    film.title.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FilmText.serif(context, size: 18, height: 1.3),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: '이 기록 열기',
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenFilm?.call(film);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    final g = _GraphColors.of(context);

    if (widget.loading) {
      return const Center(
          child:
              CircularProgressIndicator(color: Brand.amber, strokeWidth: 2));
    }
    if (widget.films.isEmpty) {
      return Center(
          child: Text('이 달에는 아직 필름이 없어요.',
              style: FilmText.caption(context, size: 14)));
    }

    return Column(children: [
      // ─── 그래프 캔버스 ───
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: g.canvas,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: c.border),
            ),
            child: LayoutBuilder(builder: (context, constraints) {
              // preserveAspectRatio "meet": 353×452 를 영역 안에 맞춤
              final s = math.min(constraints.maxWidth / _kCanvasW,
                  constraints.maxHeight / _kCanvasH);
              final ox = (constraints.maxWidth - _kCanvasW * s) / 2;
              final oy = (constraints.maxHeight - _kCanvasH * s) / 2;
              final connected = _connected;

              return AnimatedBuilder(
                animation: _entrance,
                builder: (context, _) {
                  final progress =
                      Curves.easeOut.transform(_entrance.value);
                  return Stack(children: [
                    // 엣지 레이어 (노드보다 늦게, 그려지듯 등장)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _EdgePainter(
                          nodes: {for (final n in _nodes) n.id: n},
                          edges: _edges,
                          selected: _selected,
                          edgeColor: g.edge,
                          scale: s,
                          offset: Offset(ox, oy),
                          progress: progress,
                        ),
                      ),
                    ),
                    // 노드 레이어 — 인덱스 기반 stagger fade + scale
                    for (var i = 0; i < _nodes.length; i++)
                      _staggeredNode(i, connected, g, s, ox, oy, progress),
                  ]);
                },
              );
            }),
          ),
        ),
      ),

      // 희소 데이터 안내 — 필름이 적으면 그래프가 허전한 이유를 설명해 준다
      if (widget.films.length <= 2)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('필름이 쌓일수록 연결이 풍성해져요.',
              style: FilmText.caption(context, size: 12)),
        ),

      // ─── 하단 키워드 칩 바 ───
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          children: [
            for (var i = 0; i < _topKeywords.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _chip(context, i),
            ],
          ],
        ),
      ),
      // extendBody: 유리 탭바에 가리지 않도록 하단 여백 확보
      SizedBox(height: MediaQuery.of(context).padding.bottom),
    ]);
  }

  /// 인덱스 기반 stagger — 노드가 하나씩 떠오르는 등장 연출
  Widget _staggeredNode(int i, Set<String> connected, _GraphColors g,
      double s, double ox, double oy, double progress) {
    final n = _nodes[i];
    final start = (0.04 * i).clamp(0.0, 0.5);
    final t = ((progress - start) / 0.4).clamp(0.0, 1.0);
    return Positioned(
      left: ox + (n.slot.x - n.slot.r) * s,
      top: oy + (n.slot.y - n.slot.r) * s,
      width: n.slot.r * 2 * s,
      height: n.slot.r * 2 * s,
      child: Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.8 + 0.2 * t,
          child: _buildNode(n, connected, g, s),
        ),
      ),
    );
  }

  Widget _buildNode(
      _Node n, Set<String> connected, _GraphColors g, double s) {
    final active = n.id == _selected;
    final near = connected.contains(n.id);

    switch (n.kind) {
      case _NodeKind.photo:
        Widget img = Image.network(
          n.film!.imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ColoredBox(color: g.node),
        );
        if (!near) {
          // 연결되지 않은 사진은 채도를 낮춰 은은하게 (saturate 0.7)
          img = ColorFiltered(
            colorFilter: const ColorFilter.matrix(_kDesaturate07),
            child: img,
          );
        }
        return GestureDetector(
          onTap: () => _tapPhoto(n),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: near ? Brand.amber : FilmColors.of(context).border,
                width: near ? 2 : 1,
              ),
            ),
            child: img,
          ),
        );

      case _NodeKind.label:
        final fontSize = (n.slot.r * 0.42 * s).clamp(10.0, 16.0);
        return GestureDetector(
          onTap: () => _tapLabel(n),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Brand.amber : g.node,
              border: active
                  ? null
                  : Border.all(
                      color: near
                          ? Brand.amber
                          : FilmColors.of(context).border),
              boxShadow: active
                  ? const [
                      BoxShadow(
                          color: Color(0x59E8703A), // rgba(232,112,58,0.35)
                          blurRadius: 12,
                          offset: Offset(0, 4)),
                    ]
                  : null,
            ),
            // 긴 키워드(4글자+)도 원 밖으로 넘치지 않게 scaleDown
            child: Padding(
              padding: EdgeInsets.all(n.slot.r * 0.22 * s),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  n.label!,
                  maxLines: 1,
                  style: GoogleFontsFallback.semibold(
                    context,
                    fontSize,
                    active ? Brand.onAmber : g.nodeText,
                  ),
                ),
              ),
            ),
          ),
        );

      case _NodeKind.dot:
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: near ? Brand.amber.withOpacity(0.9) : g.node,
          ),
        );
    }
  }

  Widget _chip(BuildContext context, int index) {
    final c = FilmColors.of(context);
    final (label, count) = _topKeywords[index];
    final id = 'k$index';
    final active = _selected == id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selected = active ? null : id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? Brand.amber.withOpacity(0.1) : c.bg,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: active ? Brand.amber.withOpacity(0.5) : c.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: FilmText.caption(context,
                  size: 12.5, weight: FontWeight.w500, color: c.ink)),
          const SizedBox(width: 5),
          Text('$count',
              style: FilmText.caption(context,
                  size: 12, weight: FontWeight.w600, color: Brand.amberTo)),
        ]),
      ),
    );
  }
}

/// saturate(0.7) 근사 컬러 매트릭스
const _kDesaturate07 = <double>[
  0.7639, 0.2145, 0.0216, 0, 0, //
  0.0639, 0.9145, 0.0216, 0, 0, //
  0.0639, 0.2145, 0.7216, 0, 0, //
  0, 0, 0, 1, 0,
];

/// 라벨 텍스트 스타일 헬퍼 (FilmText 와 동일 폰트, 크기 가변)
abstract class GoogleFontsFallback {
  static TextStyle semibold(BuildContext c, double size, Color color) =>
      FilmText.body(c, size: size, weight: FontWeight.w600, color: color)
          .copyWith(height: 1.1);
}

/// 곡선 엣지 레이어 — 수직 방향으로 살짝 휜 quadratic bezier
class _EdgePainter extends CustomPainter {
  final Map<String, _Node> nodes;
  final List<_Edge> edges;
  final String? selected;
  final Color edgeColor;
  final double scale;
  final Offset offset;
  final double progress; // 등장 애니메이션 (0..1) — 엣지가 그려지듯 등장

  _EdgePainter({
    required this.nodes,
    required this.edges,
    required this.selected,
    required this.edgeColor,
    required this.scale,
    required this.offset,
    this.progress = 1,
  });

  Offset _pos(_Node n) =>
      Offset(offset.dx + n.slot.x * scale, offset.dy + n.slot.y * scale);

  @override
  void paint(Canvas canvas, Size size) {
    // 노드 등장(0~0.4) 후에 엣지가 그려진다
    final drawT = ((progress - 0.35) / 0.65).clamp(0.0, 1.0);
    if (drawT == 0) return;

    for (final e in edges) {
      final na = nodes[e.a];
      final nb = nodes[e.b];
      if (na == null || nb == null) continue;

      final active = e.a == selected || e.b == selected;
      final ca = _pos(na);
      final cb = _pos(nb);

      // 엣지를 노드 중심이 아닌 원 가장자리에서 시작/끝나게 트리밍
      final dir = cb - ca;
      final dlen = dir.distance;
      final ra = na.slot.r * scale, rb = nb.slot.r * scale;
      if (dlen <= ra + rb + 4 * scale) continue; // 겹칠 만큼 가까우면 생략
      final u = dir / dlen;
      final a = ca + u * ra;
      final b = cb - u * rb;

      final d = b - a;
      final len = d.distance == 0 ? 1.0 : d.distance;
      final off = math.min(len * 0.12, 22 * scale);
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

      // 곡률 방향: 캔버스 중심에서 바깥쪽으로 휘게 → 중앙 밀집·교차 감소
      final center = Offset(size.width / 2, size.height / 2);
      final toMid = mid - center;
      final sign =
          (toMid.dx * d.dy - toMid.dy * d.dx) >= 0 ? 1.0 : -1.0;
      var ctrl = Offset(mid.dx - d.dy / len * off * sign,
          mid.dy + d.dx / len * off * sign);

      // 제어점 근처에 다른 노드가 있으면(관통 위험) 반대 방향으로 휜다
      final hit = nodes.values.any((n) {
        if (n.id == e.a || n.id == e.b || n.kind == _NodeKind.dot) {
          return false;
        }
        return (_pos(n) - ctrl).distance < (n.slot.r + 8) * scale;
      });
      if (hit) {
        ctrl = Offset(mid.dx + d.dy / len * off * sign,
            mid.dy - d.dx / len * off * sign);
      }

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (active ? 1.6 : (e.strong ? 1.2 : 0.8)) * scale
        ..color = active
            ? Brand.amber.withOpacity(0.9)
            : edgeColor.withOpacity(
                edgeColor.opacity * (e.strong ? 1.0 : 0.7));

      var path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy);

      // 등장 연출: 시작점에서부터 그려지듯 (draw-on)
      if (drawT < 1) {
        final metrics = path.computeMetrics().toList();
        if (metrics.isEmpty) continue;
        path = metrics.first.extractPath(0, metrics.first.length * drawT);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.selected != selected ||
      old.edges != edges ||
      old.scale != scale ||
      old.offset != offset ||
      old.edgeColor != edgeColor ||
      old.progress != progress;
}
