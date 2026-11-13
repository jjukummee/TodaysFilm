// 디자인 시스템 — todayfilm_demo_design(theme.css)의 토큰을 그대로 옮긴 버전.
// 토스페이먼츠 스타일: 화이트 배경, 잉크 텍스트, 앰버 단일 액센트, 부드러운 그림자.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 브랜드 고정 컬러 (라이트/다크 공통)
abstract class Brand {
  /// 필름 앰버 — 유일한 액센트 컬러
  static const amber = Color(0xFFE8843F);
  static const amberFrom = Color(0xFFE8A15D); // primary 버튼 그라데이션 시작
  static const amberTo = Color(0xFFE8703A); //   〃 끝 / 강조 텍스트
  static const onAmber = Color(0xFF191919); // 앰버 위 잉크 텍스트 (AA 대비)
  static const danger = Color(0xFFD4573F); // 삭제 등 위험 액션
  static const kakao = Color(0xFFFEE500);
}

/// 코너 반경 토큰 (theme.css --film-r-*)
abstract class Radii {
  static const card = 20.0;
  static const button = 16.0;
  static const social = 14.0;
  static const input = 12.0;
  static const group = 18.0; // 마이페이지 그룹 리스트
}

/// 모드별 팔레트. FilmColors.of(context) 로 사용.
class FilmColors {
  /// bg: 화면 배경 / surface: 인풋·세그먼트 등 낮은 표면 / elevated: 카드 표면
  final Color bg, surface, elevated, ink, sub, border;
  final BoxShadow shadow;

  const FilmColors({
    required this.bg,
    required this.surface,
    required this.elevated,
    required this.ink,
    required this.sub,
    required this.border,
    required this.shadow,
  });

  static const light = FilmColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F6F3),
    elevated: Color(0xFFFFFFFF),
    ink: Color(0xFF191919),
    sub: Color(0xFF8B8680),
    border: Color(0xFFECEAE5),
    shadow: BoxShadow(
      color: Color(0x0F191919), // rgba(25,25,25,0.06)
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  );

  static const dark = FilmColors(
    bg: Color(0xFF16171D),
    surface: Color(0xFF20222B),
    elevated: Color(0xFF20222B),
    ink: Color(0xFFF2EFE9),
    sub: Color(0xFF9A948C),
    border: Color(0xFF2C2E38),
    shadow: BoxShadow(
      color: Color(0x66000000), // rgba(0,0,0,0.4)
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  );

  static FilmColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// 카드 공통 데코레이션 (radius 20 + hairline border + soft shadow)
  BoxDecoration card({double radius = Radii.card}) => BoxDecoration(
        color: elevated,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: [shadow],
      );
}

/// 타이포그래피.
/// - display/title/body/caption: Noto Sans KR (Pretendard 대응 — 토스 톤)
/// - serif: Nanum Myeongjo (필름 제목 전용 세리프)
abstract class FilmText {
  static TextStyle _sans(
    BuildContext c, {
    required double size,
    required FontWeight weight,
    double height = 1.4,
    double letterSpacing = -0.2,
    Color? color,
  }) =>
      GoogleFonts.notoSansKr(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color ?? FilmColors.of(c).ink,
      );

  /// 화면 대표 헤드라인 (24–26 / bold / -0.02em)
  static TextStyle display(BuildContext c, {double size = 26, Color? color}) =>
      _sans(c,
          size: size,
          weight: FontWeight.w700,
          height: 1.35,
          letterSpacing: size * -0.02,
          color: color);

  /// 섹션/카드 타이틀 (15–17 / semibold)
  static TextStyle title(BuildContext c,
          {double size = 17, Color? color, FontWeight weight = FontWeight.w600}) =>
      _sans(c,
          size: size,
          weight: weight,
          height: 1.4,
          letterSpacing: size * -0.01,
          color: color);

  /// 본문 (13–15 / regular)
  static TextStyle body(BuildContext c,
          {double size = 14,
          Color? color,
          FontWeight weight = FontWeight.w400,
          double height = 1.55}) =>
      _sans(c, size: size, weight: weight, height: height, color: color);

  /// 캡션 (11–13 / sub 컬러 기본)
  static TextStyle caption(BuildContext c,
          {double size = 12,
          Color? color,
          FontWeight weight = FontWeight.w400,
          double height = 1.4}) =>
      _sans(c,
          size: size,
          weight: weight,
          height: height,
          color: color ?? FilmColors.of(c).sub);

  /// 필름 제목 세리프 (사진 위 오버레이 등)
  static TextStyle serif(BuildContext c,
          {double size = 24, Color? color, double height = 1.4}) =>
      GoogleFonts.nanumMyeongjo(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: height,
        color: color ?? FilmColors.of(c).ink,
      );

  /// 오버라인 라벨 ("TODAY'S FILM" 등 — 대문자 트래킹)
  static TextStyle overline(BuildContext c, {Color? color}) =>
      GoogleFonts.notoSansKr(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
        color: color ?? Brand.amberTo,
      );
}

ThemeData buildTheme(Brightness brightness) {
  final colors =
      brightness == Brightness.dark ? FilmColors.dark : FilmColors.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Brand.amber,
      brightness: brightness,
      surface: colors.bg,
    ),
    splashFactory: NoSplash.splashFactory, // 토스식: 잉크 스플래시 대신 scale/음영 피드백
    highlightColor: colors.ink.withOpacity(0.04),
    textTheme: GoogleFonts.notoSansKrTextTheme(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
    ),
    dividerColor: colors.border,
  );
}
