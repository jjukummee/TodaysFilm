// 스모크 테스트 — 앱이 크래시 없이 첫 프레임(로그인 화면)을 그리는지 확인.
import 'package:flutter_test/flutter_test.dart';

import 'package:todays_film/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const TodaysFilmApp());
    expect(find.text('오늘의 필름'), findsWidgets);
  });
}
