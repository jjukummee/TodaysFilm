// 하단 탭 셸 — demo_design kit.tsx TabBar + 리퀴드 글래스.
// extendBody로 콘텐츠가 유리 탭바 아래로 스크롤되어 지나간다 (재질이 사는 조건).
// 아이콘 24, 라벨 11 medium, 활성 = 앰버.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../main.dart';
import 'archive_screen.dart';
import 'home_screen.dart';
import 'my_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  static const _tabs = [
    (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: '홈'),
    (
      icon: Icons.photo_library_outlined,
      activeIcon: Icons.photo_library_rounded,
      label: '아카이브'
    ),
    (
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: '마이'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: rootTabNotifier,
      builder: (context, index, _) {
        return Scaffold(
          extendBody: true, // 콘텐츠가 유리 탭바 아래로 지나가야 재질이 산다
          body: IndexedStack(
            index: index,
            children: [
              HomeScreen(onGoArchive: () => rootTabNotifier.value = 1),
              const ArchiveScreen(),
              const MyScreen(),
            ],
          ),
          bottomNavigationBar: GlassPanel(
            radius: BorderRadius.zero,
            topEdgeOnly: true,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: List.generate(_tabs.length, (i) {
                    final tab = _tabs[i];
                    final active = index == i;
                    final color = active ? Brand.amber : c.sub;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          rootTabNotifier.value = i;
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(active ? tab.activeIcon : tab.icon,
                                size: 24, color: color),
                            const SizedBox(height: 3),
                            Text(
                              tab.label,
                              style: FilmText.caption(context,
                                  size: 11,
                                  weight: FontWeight.w500,
                                  color: color,
                                  height: 1.2),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
