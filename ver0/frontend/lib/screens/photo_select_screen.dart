// 사진 선택 — demo_design flow-screens.tsx PhotoSelectScreen 대응.
// NavHeader → 헤드라인 → 3열 사진 그리드(선택 순번 배지) → 하단 Primary CTA.
//
// 실기기: photo_manager 로 오늘 찍은 사진을 불러온다.
// 갤러리 접근 불가(권한 거부/데스크톱)면 데모 이미지 그리드로 폴백.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/demo_data.dart';
import 'question_screen.dart';

const kMaxSelect = 3; // 백엔드는 5장까지 지원

class _GalleryItem {
  final String id;
  final AssetEntity? asset; // 실제 갤러리 사진
  final String? demoUrl; // 데모 폴백
  _GalleryItem({required this.id, this.asset, this.demoUrl});
}

class PhotoSelectScreen extends StatefulWidget {
  const PhotoSelectScreen({super.key});

  @override
  State<PhotoSelectScreen> createState() => _PhotoSelectScreenState();
}

class _PhotoSelectScreenState extends State<PhotoSelectScreen> {
  List<_GalleryItem> _items = [];
  final List<String> _selected = [];
  bool _limitedAccess = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        _fallbackToDemo();
        return;
      }
      _limitedAccess = permission == PermissionState.limited; // iOS 일부 허용

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: FilterOptionGroup(
          createTimeCond: DateTimeCond(min: startOfDay, max: now),
          orders: [const OrderOption(type: OrderOptionType.createDate)],
        ),
      );
      if (paths.isEmpty) {
        _fallbackToDemo();
        return;
      }
      final assets = await paths.first.getAssetListPaged(page: 0, size: 120);
      if (assets.isEmpty) {
        _fallbackToDemo();
        return;
      }
      setState(() {
        _items =
            assets.map((a) => _GalleryItem(id: a.id, asset: a)).toList();
        _loading = false;
      });
    } catch (_) {
      _fallbackToDemo();
    }
  }

  void _fallbackToDemo() {
    setState(() {
      _items = List.generate(
        demoGalleryUrls.length,
        (i) => _GalleryItem(id: 'demo_$i', demoUrl: demoGalleryUrls[i]),
      );
      _loading = false;
    });
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length < kMaxSelect) {
        _selected.add(id);
      } else {
        showFilmSnack(context, '사진은 최대 $kMaxSelect장까지 고를 수 있어요.');
      }
    });
  }

  Future<void> _goNext() async {
    // 선택된 사진의 바이트 수집 (업로드/질문 화면 미리보기용)
    final selectedItems =
        _selected.map((id) => _items.firstWhere((e) => e.id == id)).toList();
    final List<Uint8List?> bytes = [];
    for (final item in selectedItems) {
      if (item.asset != null) {
        bytes.add(await item.asset!
            .thumbnailDataWithSize(const ThumbnailSize(1024, 1024)));
      } else {
        bytes.add(null); // 데모 모드: URL 기반
      }
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QuestionScreen(
        photoBytes: bytes,
        demoUrls: selectedItems.map((e) => e.demoUrl).toList(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const NavHeader(),

          // ─── 헤드라인 ───
          Padding(
            padding: kPageHPad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text('오늘의 사진을 골라주세요',
                      style: FilmText.display(context, size: 24)),
                ),
                const SizedBox(height: 8),
                Text('오늘을 담은 사진 몇 장이면 충분해요. (최대 $kMaxSelect장)',
                    style: FilmText.caption(context, size: 14)),
              ],
            ),
          ),

          // 제한된 접근 배너 (iOS Limited Access)
          if (_limitedAccess)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: GestureDetector(
                onTap: () => PhotoManager.presentLimited(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Brand.amber.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(Radii.input),
                  ),
                  child: Row(children: [
                    const Icon(Icons.add_photo_alternate_outlined,
                        size: 16, color: Brand.amberTo),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('일부 사진만 허용돼 있어요',
                          style: FilmText.caption(context,
                              size: 13, color: c.ink)),
                    ),
                    Text('더 추가하기',
                        style: FilmText.caption(context,
                            size: 13,
                            weight: FontWeight.w600,
                            color: Brand.amberTo)),
                  ]),
                ),
              ),
            ),

          // ─── 사진 그리드 + 유리 CTA 바 ───
          // 그리드가 유리 바 아래로 스크롤되어 지나간다 (리퀴드 글래스 조건)
          Expanded(
            child: Stack(children: [
              _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Brand.amber, strokeWidth: 2))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 108),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, i) =>
                          _buildGridTile(context, _items[i]),
                    ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: GlassPanel(
                  radius: BorderRadius.zero,
                  topEdgeOnly: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: PrimaryButton(
                      label: '이 사진들로 돌아보기',
                      onPressed: _selected.isEmpty ? null : _goNext,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildGridTile(BuildContext context, _GalleryItem item) {
    final c = FilmColors.of(context);
    final idx = _selected.indexOf(item.id);
    final isSel = idx >= 0;

    Widget photo;
    if (item.asset != null) {
      photo = FutureBuilder<Uint8List?>(
        future:
            item.asset!.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
        builder: (context, snap) => snap.hasData
            ? Image.memory(snap.data!, fit: BoxFit.cover)
            : Container(color: c.surface),
      );
    } else {
      photo = Image.network(item.demoUrl!, fit: BoxFit.cover,
          loadingBuilder: (c2, child, p) =>
              p == null ? child : Container(color: c.surface),
          errorBuilder: (_, __, ___) => Container(color: c.surface));
    }

    return GestureDetector(
      onTap: () => _toggle(item.id),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.input),
        child: Stack(fit: StackFit.expand, children: [
          photo,
          // 선택 시 딤
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: isSel ? 1 : 0,
            child: Container(color: Colors.black.withOpacity(0.25)),
          ),
          // 선택 순번 배지
          Positioned(
            top: 6,
            right: 6,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSel ? Brand.amber : Colors.black.withOpacity(0.25),
                shape: BoxShape.circle,
                border: isSel
                    ? null
                    : Border.all(
                        color: Colors.white.withOpacity(0.8), width: 1.5),
              ),
              child: isSel
                  ? Center(
                      child: Text('${idx + 1}',
                          style: FilmText.caption(context,
                              size: 11,
                              weight: FontWeight.w600,
                              color: Brand.onAmber,
                              height: 1)))
                  : null,
            ),
          ),
        ]),
      ),
    );
  }
}
