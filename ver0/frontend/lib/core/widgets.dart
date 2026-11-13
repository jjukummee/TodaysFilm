// 공용 위젯 — demo_design kit.tsx / icons.tsx 대응.
// PrimaryButton(56·앰버 그라데이션), SecondaryButton, SocialButton,
// FilmTextField(52), FilmMark(브랜드 로고), NavHeader, PressableScale,
// GlassPanel(리퀴드 글래스 근사 재질) 등.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// 탭 시 살짝 눌리는 토스식 피드백 (active:scale-0.985)
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.985,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? widget.pressedScale : 1,
        child: widget.child,
      ),
    );
  }
}

/// 브랜드 마크 — 필름 프레임 + 셔터 조리개 (icons.tsx FilmMark)
class FilmMark extends StatelessWidget {
  final double size;
  final Color? color;
  const FilmMark({super.key, this.size = 40, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FilmMarkPainter(color ?? Brand.amber),
    );
  }
}

class _FilmMarkPainter extends CustomPainter {
  final Color color;
  _FilmMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48; // viewBox 48 기준 스케일
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * s;
    final fill = Paint()..color = color;

    // 프레임
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(6 * s, 9 * s, 36 * s, 30 * s),
        Radius.circular(8 * s),
      ),
      stroke,
    );
    // 스프로킷 홀 (좌 3 + 우 3)
    for (final x in [11.0, 33.8]) {
      for (final y in [14.0, 22.4, 30.8]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x * s, y * s, 3.2 * s, 3.2 * s),
            Radius.circular(1 * s),
          ),
          fill,
        );
      }
    }
    // 셔터 조리개
    canvas.drawCircle(Offset(24 * s, 24 * s), 5.4 * s, stroke);
  }

  @override
  bool shouldRepaint(covariant _FilmMarkPainter old) => old.color != color;
}

/// Primary 버튼 — 56px, radius 16, 앰버 그라데이션, 잉크 텍스트
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const PrimaryButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return PressableScale(
      onTap: onPressed,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.4,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Brand.amberFrom, Brand.amberTo],
            ),
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          child: Text(
            label,
            style: FilmText.title(context, size: 16, color: Brand.onAmber),
          ),
        ),
      ),
    );
  }
}

/// Secondary 버튼 — 56px, surface 배경, 잉크 텍스트
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const SecondaryButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    return PressableScale(
      onTap: onPressed,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.button),
        ),
        child: Text(label, style: FilmText.title(context, size: 16)),
      ),
    );
  }
}

/// 소셜 버튼 — 54px, radius 14, 아이콘 좌측 / 라벨 중앙
class SocialButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final VoidCallback? onPressed;
  const SocialButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    this.borderColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onPressed,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Radii.social),
          border: borderColor != null ? Border.all(color: borderColor!) : null,
        ),
        child: Stack(alignment: Alignment.center, children: [
          Positioned(left: 16, child: icon),
          Text(label,
              style: FilmText.title(context, size: 15, color: foreground)),
        ]),
      ),
    );
  }
}

/// 인풋 필드 — 52px, radius 12, surface 배경, 포커스 시 앰버 보더
class FilmTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  const FilmTextField({
    super.key,
    this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    final radius = maxLines > 1 ? Radii.button : Radii.input;
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      style: FilmText.body(context, size: 15),
      cursorColor: Brand.amber,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: FilmText.body(context, size: 15, color: c.sub),
        filled: true,
        fillColor: c.surface,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
            horizontal: 16, vertical: maxLines > 1 ? 16 : 15.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Brand.amber, width: 1.2),
        ),
      ),
    );
  }
}

/// 뒤로가기 헤더 (nav.tsx NavHeader) — ‹ 버튼 + 선택적 타이틀
class NavHeader extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final VoidCallback? onBack;
  const NavHeader({super.key, this.title, this.trailing, this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    return SizedBox(
      height: 48,
      child: Row(children: [
        const SizedBox(width: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.chevron_left, size: 28, color: c.ink),
          ),
        ),
        if (title != null)
          Text(title!, style: FilmText.title(context, size: 16)),
        const Spacer(),
        if (trailing != null) ...[trailing!, const SizedBox(width: 12)],
      ]),
    );
  }
}

/// 토스식 토글 스위치 (46×28)
class FilmToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const FilmToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? Brand.amber : c.border,
          borderRadius: BorderRadius.circular(100),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 2,
                    offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 확인용 바텀시트 (demo_design의 sheet — "회고를 그만둘까요?" 등)
Future<T?> showFilmSheet<T>(BuildContext context, {required Widget child}) {
  final c = FilmColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: c.elevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          child,
        ]),
      ),
    ),
  );
}

/// 필름이 없는 날/빈 상태 등에서 쓰는 스낵바 (잉크 배경)
void showFilmSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    backgroundColor: const Color(0xFF191919),
    content: Text(message,
        style: FilmText.body(context, size: 14, color: Colors.white)),
  ));
}

/// 리퀴드 글래스 근사 재질 — 기능 레이어(탭바·플로팅 컨트롤 바) 전용.
/// 콘텐츠 카드에는 쓰지 않는다 (liquid-glass-design 스킬 대원칙).
///
/// 5요소 중 4개 구현: 블러+채도 부스트 / 림 하이라이트 / 스펙큘러 / 적응형 틴트.
/// (굴절은 셰이더 필요 — liquid_glass_renderer 도입 시 이 위젯만 교체하면 됨)
class GlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;

  /// true면 상단 가장자리에만 림 하이라이트 (전폭 하단 바 용도)
  final bool topEdgeOnly;
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(24)),
    this.topEdgeOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    // 접근성: 고대비(투명도 감소) 설정이면 불투명 폴백
    if (MediaQuery.of(context).highContrast) {
      final c = FilmColors.of(context);
      return Container(
        decoration: BoxDecoration(color: c.bg, borderRadius: radius),
        child: child,
      );
    }

    final rim = dark ? const Color(0x2EFFFFFF) : const Color(0x73FFFFFF);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        // 블러 + 채도 부스트 (saturate 없으면 안개처럼 보임)
        filter: ui.ImageFilter.compose(
          outer: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          inner: ColorFilter.matrix(_saturationMatrix(1.6)),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            // 적응형 틴트 (라이트: 흰색 55% — 텍스트 가독성 / 다크: 검정 45%)
            color: dark ? const Color(0x7314151B) : const Color(0x8CFFFFFF),
            // 림 하이라이트 — 광원(상단) 방향 밝은 라인
            border: topEdgeOnly
                ? Border(top: BorderSide(color: rim))
                : Border.all(color: rim),
            // 스펙큘러 — 사선으로 스치는 빛
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [const Color(0x1AFFFFFF), const Color(0x00FFFFFF)]
                  : [const Color(0x40FFFFFF), const Color(0x00FFFFFF)],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 채도 행렬 (s = 배율)
List<double> _saturationMatrix(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
  return [
    sr + s, sg, sb, 0, 0, //
    sr, sg + s, sb, 0, 0, //
    sr, sg, sb + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// 스크린 좌우 공통 패딩 (demo_design px-5 = 20)
const kPageHPad = EdgeInsets.symmetric(horizontal: 20);
