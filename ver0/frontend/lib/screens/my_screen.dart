// 마이 — demo_design my-screen.tsx 대응. 토스식 그룹 리스트.
// 프로필 카드 → 스탯 3분할 → 섹션(기록/알림/개인정보·데이터/계정) → 회원 탈퇴.
//
// 백엔드 연동: GET /auth/me (프로필), GET /auth/me/stats (통계).
// 데모 모드(비로그인)에서는 게스트 프로필 + 샘플 통계로 동작.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../main.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  final _api = ApiService.instance;

  String _nickname = '게스트';
  String _email = '';
  int _totalFilms = 0;
  int _streak = 0;
  int _questions = 0;

  bool _eveningAlarm = true;
  String _filmStyle = '클래식 세피아';
  static const _filmStyles = ['클래식 세피아', '모노크롬', '비비드 컬러'];

  bool get _demo => !_api.isLoggedIn;

  // 데모 통계
  static const demoStatsFilms = 12;
  static const demoStatsStreak = 4;
  static const demoStatsQuestions = 38;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    if (_demo) {
      _nickname = '게스트';
      _totalFilms = demoStatsFilms;
      _streak = demoStatsStreak;
      _questions = demoStatsQuestions;
    } else {
      _load();
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _eveningAlarm = prefs.getBool('evening_alarm') ?? true;
      _filmStyle = prefs.getString('film_style') ?? _filmStyles.first;
    });
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_api.me(), _api.myStats()]);
      if (!mounted) return;
      setState(() {
        _nickname = results[0]['nickname'] ?? '';
        _email = results[0]['email'] ?? '';
        _totalFilms = results[1]['total_films'] ?? 0;
        _streak = results[1]['streak_days'] ?? 0;
        _questions = results[1]['questions_received'] ?? 0;
      });
    } catch (_) {
      if (mounted) showFilmSnack(context, '서버에 연결할 수 없어요.');
    }
  }

  // ─── 액션 ─────────────────────────────────────

  Future<void> _toggleEveningAlarm(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _eveningAlarm = value);
    await prefs.setBool('evening_alarm', value);
  }

  Future<void> _pickFilmStyle() async {
    final c = FilmColors.of(context);
    final picked = await showFilmSheet<String>(
      context,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('필름 스타일', style: FilmText.title(context, size: 17)),
        const SizedBox(height: 16),
        for (final style in _filmStyles)
          Builder(builder: (sheetContext) {
            final selected = style == _filmStyle;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(sheetContext).pop(style),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: selected ? Brand.amber.withOpacity(0.08) : c.surface,
                  borderRadius: BorderRadius.circular(Radii.input),
                  border: selected
                      ? Border.all(color: Brand.amber.withOpacity(0.5))
                      : null,
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(style,
                        style: FilmText.body(context,
                            size: 15,
                            weight:
                                selected ? FontWeight.w600 : FontWeight.w400)),
                  ),
                  if (selected)
                    const Icon(Icons.check, size: 18, color: Brand.amberTo),
                ]),
              ),
            );
          }),
      ]),
    );
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('film_style', picked);
    setState(() => _filmStyle = picked);
  }

  Future<void> _openPrivacy() async {
    final c = FilmColors.of(context);
    await showFilmSheet(
      context,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('개인정보 및 보안', style: FilmText.title(context, size: 17)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.input),
          ),
          child: Row(children: [
            Icon(Icons.mail_outline, size: 18, color: c.sub),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('로그인 계정', style: FilmText.body(context, size: 14)),
                  Text(_demo ? '데모 모드 (로그인 안 됨)' : _email,
                      style: FilmText.caption(context, size: 12)),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.input),
          ),
          child: Row(children: [
            Icon(Icons.lock_outline, size: 18, color: c.sub),
            const SizedBox(width: 12),
            Expanded(
              child: Text('회고 답변은 안전하게 저장돼요',
                  style: FilmText.body(context, size: 14)),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    if (_demo) {
      showFilmSnack(context, '데모 모드에서는 탈퇴할 계정이 없어요.');
      return;
    }
    final ok = await _confirm('계정을 삭제할까요?', '모든 필름과 기록이 영구 삭제되고 되돌릴 수 없어요.',
        confirmLabel: '삭제');
    if (ok != true) return;
    try {
      await _api.deleteAccount();
      _goLogin();
    } on ApiException catch (e) {
      if (mounted) showFilmSnack(context, e.message);
    } catch (_) {
      if (mounted) showFilmSnack(context, '서버에 연결할 수 없어요.');
    }
  }

  Future<void> _openHelp() async {
    await showFilmSheet(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child:
                  Text('오늘의 필름 사용법', style: FilmText.title(context, size: 17))),
          const SizedBox(height: 16),
          Text(
            '1. 홈에서 "오늘의 필름 만들기"를 눌러 오늘 찍은 사진을 골라요.\n\n'
            '2. 질문 3개에 짧게 답해요. 한 문장이면 충분해요.\n\n'
            '3. 하루가 한 편의 필름(제목·내레이션·키워드)으로 완성돼요.\n\n'
            '4. 아카이브에서 지난 필름들을 캘린더로 모아볼 수 있어요.',
            style: FilmText.body(context, size: 14, height: 1.7),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: '확인',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    if (_demo) {
      _goLogin();
      return;
    }
    final ok = await _confirm('로그아웃할까요?', '다시 로그인하면 기록을 이어서 볼 수 있어요.',
        confirmLabel: '로그아웃');
    if (ok != true) return;
    await _api.logout();
    _goLogin();
  }

  void _goLogin() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  Future<bool?> _confirm(String title, String message,
      {required String confirmLabel}) {
    final c = FilmColors.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.elevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
        title: Text(title, style: FilmText.title(context, size: 17)),
        content: Text(message,
            style: FilmText.body(context, size: 14, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('취소', style: FilmText.caption(context, size: 14)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel,
                style: FilmText.body(context,
                    size: 14, color: Brand.danger, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ─── UI ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: ListView(
        // extendBody: 유리 탭바에 가리지 않도록 하단 여백 확보
        padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.of(context).padding.bottom),
        children: [
          // ─── 헤더 ───
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('마이', style: FilmText.display(context, size: 22)),
          ),

          // ─── 프로필 카드 ───
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: c.card(radius: Radii.group),
              child: Row(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration:
                      BoxDecoration(color: c.surface, shape: BoxShape.circle),
                  child:
                      Icon(Icons.person_outline_rounded, size: 28, color: c.sub),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_nickname, style: FilmText.title(context, size: 17)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(_demo ? '데모 모드' : '이메일로 로그인 중',
                            style: FilmText.caption(context,
                                size: 11,
                                weight: FontWeight.w500,
                                height: 1.3)),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),

          // ─── 스탯 3분할 ───
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: c.card(radius: Radii.group),
              child: Row(children: [
                _stat('$_totalFilms', '편', '필름', false),
                _statDivider(c),
                _stat('$_streak', '일', '연속 기록', true),
                _statDivider(c),
                _stat('$_questions', '개', '받은 질문', false),
              ]),
            ),
          ),

          // ─── 섹션: 환경설정 ───
          Padding(
            padding: kPageHPad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('환경설정'),
                _group([
                  _RowSpec(
                    icon: isDark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    label: '다크 모드',
                    trailing: FilmToggle(
                      value: isDark,
                      onChanged: (v) => themeModeNotifier.value =
                          v ? ThemeMode.dark : ThemeMode.light,
                    ),
                  ),
                  _RowSpec(
                    icon: Icons.notifications_none_rounded,
                    label: '저녁 리마인드',
                    caption: _eveningAlarm ? '매일 밤 21:00' : '꺼짐',
                    trailing: FilmToggle(
                      value: _eveningAlarm,
                      onChanged: _toggleEveningAlarm,
                    ),
                  ),
                  _RowSpec(
                    icon: Icons.style_outlined,
                    label: '필름 스타일',
                    value: _filmStyle,
                    onTap: _pickFilmStyle,
                  ),
                ]),

                _sectionHeader('개인정보 · 데이터'),
                _group([
                  _RowSpec(
                    icon: Icons.lock_outline_rounded,
                    label: '개인정보 및 보안',
                    onTap: _openPrivacy,
                  ),
                  _RowSpec(
                    icon: Icons.file_upload_outlined,
                    label: '데이터 내보내기',
                    caption: '내 기록 백업 (PDF · 이미지)',
                    onTap: () => showFilmSnack(context, '내보내기 기능은 준비 중이에요.'),
                  ),
                ]),

                _sectionHeader('계정'),
                _group([
                  _RowSpec(
                    icon: Icons.help_outline_rounded,
                    label: '도움말',
                    onTap: _openHelp,
                  ),
                  _RowSpec(
                    icon: Icons.info_outline_rounded,
                    label: '앱 버전',
                    value: 'v0.1.0',
                    chevron: false,
                  ),
                  _RowSpec(
                    icon: _demo ? Icons.login_rounded : Icons.logout_rounded,
                    label: _demo ? '로그인' : '로그아웃',
                    onTap: _logout,
                  ),
                ]),

                // 회원 탈퇴 — 가장 아래, 낮은 위계
                if (!_demo)
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _confirmDeleteAccount,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 20, horizontal: 24),
                        child: Text(
                          '회원 탈퇴',
                          style: FilmText.caption(context,
                                  size: 13, color: const Color(0xFFC98A7C))
                              .copyWith(
                                  decoration: TextDecoration.underline,
                                  decorationColor: const Color(0xFFC98A7C)),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String unit, String label, bool accent) {
    final c = FilmColors.of(context);
    return Expanded(
      child: Column(children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: value,
                style: FilmText.display(context,
                    size: 24, color: accent ? Brand.amberTo : c.ink)),
            TextSpan(
                text: unit,
                style: FilmText.title(context,
                    size: 15, color: accent ? Brand.amberTo : c.ink)),
          ]),
        ),
        const SizedBox(height: 2),
        Text(label, style: FilmText.caption(context, size: 12)),
      ]),
    );
  }

  Widget _statDivider(FilmColors c) =>
      Container(width: 1, height: 36, color: c.border);

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(title,
            style: FilmText.caption(context, size: 13, weight: FontWeight.w500)),
      );

  /// 그룹(카드) 컨테이너 — 행 사이 hairline divider
  Widget _group(List<_RowSpec> rows) {
    final c = FilmColors.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: c.card(radius: Radii.group),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Container(height: 1, color: c.border),
          _row(rows[i]),
        ],
      ]),
    );
  }

  Widget _row(_RowSpec spec) {
    final c = FilmColors.of(context);
    return InkWell(
      onTap: spec.onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          Icon(spec.icon, size: 20, color: c.sub),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(spec.label,
                    style: FilmText.body(context,
                        size: 15,
                        height: 1.4,
                        color: c.ink)),
                if (spec.caption != null)
                  Text(spec.caption!,
                      style: FilmText.caption(context, size: 12)),
              ],
            ),
          ),
          if (spec.value != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(spec.value!,
                  style: FilmText.body(context, size: 14, color: c.sub)),
            ),
          if (spec.trailing != null)
            spec.trailing!
          else if (spec.chevron && spec.onTap != null)
            Icon(Icons.chevron_right, size: 18, color: c.sub),
        ]),
      ),
    );
  }
}

class _RowSpec {
  final IconData icon;
  final String label;
  final String? caption;
  final String? value;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;
  _RowSpec({
    required this.icon,
    required this.label,
    this.caption,
    this.value,
    this.trailing,
    this.chevron = true,
    this.onTap,
  });
}
