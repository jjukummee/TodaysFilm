// 로그인 — demo_design login-screen.tsx 대응.
// 브랜드 영역(FilmMark) → 이메일/비밀번호 → Primary 로그인 → 링크 행
// → "또는" 구분선 → 소셜 버튼(카카오/Apple/Google) → 약관 캡션.
//
// 기능은 기존 그대로: 이메일 로그인/회원가입 + 데모 모드 둘러보기.
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api_service.dart';
import 'root_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _nickname = TextEditingController();
  bool _signupMode = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final nickname = _nickname.text.trim();
    if (email.isEmpty || password.isEmpty) {
      showFilmSnack(context, '이메일과 비밀번호를 입력해 주세요.');
      return;
    }
    if (_signupMode && nickname.isEmpty) {
      showFilmSnack(context, '닉네임을 입력해 주세요.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_signupMode) {
        await ApiService.instance.signup(email, password, nickname);
      } else {
        await ApiService.instance.login(email, password);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RootShell()));
    } on ApiException catch (e) {
      showFilmSnack(context, e.message);
    } catch (_) {
      showFilmSnack(context, '서버에 연결할 수 없어요. 백엔드가 실행 중인지 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _enterDemo() {
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RootShell()));
  }

  void _socialNotReady() =>
      showFilmSnack(context, '소셜 로그인은 준비 중이에요. 이메일로 시작해 주세요.');

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            // ─── 브랜드 영역 ───
            Padding(
              padding: const EdgeInsets.only(top: 64, bottom: 36),
              child: Column(children: [
                const FilmMark(size: 46),
                const SizedBox(height: 20),
                Text('오늘의 필름', style: FilmText.display(context, size: 24)),
                const SizedBox(height: 8),
                Text('하루를 한 편의 필름으로 남겨요.',
                    style: FilmText.caption(context, size: 13)),
              ]),
            ),

            // ─── 이메일 로그인 (주 영역) ───
            if (_signupMode) ...[
              FilmTextField(controller: _nickname, hint: '닉네임'),
              const SizedBox(height: 12),
            ],
            FilmTextField(
              controller: _email,
              hint: '이메일',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            FilmTextField(
              controller: _password,
              hint: '비밀번호 (8자 이상)',
              obscure: true,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: _busy
                  ? '잠시만요...'
                  : (_signupMode ? '가입하고 시작하기' : '로그인'),
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: 14),

            // 링크 행: 모드 전환 · 둘러보기
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              GestureDetector(
                onTap: _busy
                    ? null
                    : () => setState(() => _signupMode = !_signupMode),
                child: Text(
                  _signupMode ? '이미 계정이 있어요' : '이메일로 회원가입',
                  style: FilmText.caption(context,
                      size: 13,
                      weight: FontWeight.w600,
                      color: Brand.amberTo),
                ),
              ),
              Container(
                width: 1,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: c.border,
              ),
              GestureDetector(
                onTap: _busy ? null : _enterDemo,
                child: Text('로그인 없이 둘러보기',
                    style: FilmText.caption(context, size: 13)),
              ),
            ]),
            const SizedBox(height: 20),

            // ─── "또는" 구분선 ───
            Row(children: [
              Expanded(child: Container(height: 1, color: c.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('또는',
                    style: FilmText.caption(context,
                        size: 12, weight: FontWeight.w500)),
              ),
              Expanded(child: Container(height: 1, color: c.border)),
            ]),
            const SizedBox(height: 20),

            // ─── 소셜 로그인 (보조 영역) ───
            SocialButton(
              icon: const Icon(Icons.chat_bubble,
                  size: 18, color: Color(0xFF191919)),
              label: '카카오로 시작하기',
              background: Brand.kakao,
              foreground: const Color(0xFF191919),
              onPressed: _socialNotReady,
            ),
            const SizedBox(height: 12),
            SocialButton(
              icon: const Icon(Icons.apple, size: 22, color: Colors.white),
              label: 'Apple로 시작하기',
              background: Colors.black,
              foreground: Colors.white,
              onPressed: _socialNotReady,
            ),
            const SizedBox(height: 12),
            SocialButton(
              icon: Text('G',
                  style: FilmText.title(context, size: 17, color: c.ink)),
              label: 'Google로 시작하기',
              background: c.bg,
              foreground: c.ink,
              borderColor: c.border,
              onPressed: _socialNotReady,
            ),
            const SizedBox(height: 28),

            // ─── 약관 캡션 ───
            Text.rich(
              TextSpan(
                style: FilmText.caption(context, size: 11, height: 1.6),
                children: const [
                  TextSpan(text: '계속하면 '),
                  TextSpan(
                      text: '서비스 약관',
                      style: TextStyle(decoration: TextDecoration.underline)),
                  TextSpan(text: '과 '),
                  TextSpan(
                      text: '개인정보처리방침',
                      style: TextStyle(decoration: TextDecoration.underline)),
                  TextSpan(text: '에\n동의하게 됩니다.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
