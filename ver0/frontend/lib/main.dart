import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme.dart';
import 'screens/login_screen.dart';
import 'screens/root_shell.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.instance.restoreSession();
  runApp(const TodaysFilmApp());
}

/// 전역 테마 모드 (디자인의 🌙/☀️ 토글)
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

/// 루트 셸의 현재 탭 (0 홈 · 1 아카이브 · 2 마이).
/// 필름 결과 화면 등 스택 위 화면에서 홈으로 빠져나오며 탭을 지정할 때 쓴다.
final rootTabNotifier = ValueNotifier<int>(0);

class TodaysFilmApp extends StatelessWidget {
  const TodaysFilmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        SystemChrome.setSystemUIOverlayStyle(
          mode == ThemeMode.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
        );
        return MaterialApp(
          title: '오늘의 필름',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: mode,
          // 저장된 토큰이 있으면 바로 홈, 없으면 로그인부터
          home: ApiService.instance.isLoggedIn
              ? const RootShell()
              : const LoginScreen(),
        );
      },
    );
  }
}
