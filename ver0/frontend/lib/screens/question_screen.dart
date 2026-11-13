// 회고 대화 — demo_design flow-screens.tsx RetroChatScreen 대응.
// 상단 ‹(중단 확인 시트) + "n / 3" → 브랜드 라벨 + 큰 질문 → 답변 입력 + Primary CTA.
//
// 백엔드 연동: 로그인 상태면 실제 API 호출, 아니면 데모 질문으로 동작.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api_service.dart';
import '../services/demo_data.dart';
import 'film_result_screen.dart';

const kTotalQuestions = 3;

class QuestionScreen extends StatefulWidget {
  final List<Uint8List?> photoBytes;
  final List<String?> demoUrls;
  const QuestionScreen(
      {super.key, required this.photoBytes, required this.demoUrls});

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  final _controller = TextEditingController();
  final _api = ApiService.instance;

  String? _recordId;
  String? _questionId;
  String _question = '';
  int _step = 0; // 0..2
  bool _loading = true;
  bool _submitting = false;

  bool get _demo => !_api.isLoggedIn;
  bool get _last => _step >= kTotalQuestions - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_demo) {
      setState(() {
        _question = demoQuestions[0];
        _loading = false;
      });
      return;
    }
    try {
      // 1) 사진 업로드 → 2) 기록 생성 → 3) 첫 질문
      // 갤러리 접근 불가 폴백(데모 URL)이면 이미지를 내려받아 실제로 업로드한다.
      final bytes = <Uint8List>[];
      for (var i = 0; i < widget.photoBytes.length; i++) {
        final b = widget.photoBytes[i];
        if (b != null) {
          bytes.add(b);
        } else if (widget.demoUrls[i] != null) {
          final res = await http.get(Uri.parse(widget.demoUrls[i]!));
          bytes.add(res.bodyBytes);
        }
      }
      final photos = await _api.uploadPhotos(bytes);
      final ids = photos.map((p) => p['id'] as String).toList();
      final record = await _api.createRecord(ids, ids.first);
      _recordId = record['id'];
      final q = await _api.nextQuestion(_recordId!);
      setState(() {
        _questionId = q['id'];
        _question = q['question_text'];
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } catch (_) {
      if (mounted) _showError('서버에 연결할 수 없어요. 백엔드가 실행 중인지 확인해 주세요.');
    }
  }

  Future<void> _submit({bool skipped = false}) async {
    final text = _controller.text.trim();
    if (!skipped && text.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);

    try {
      if (!_demo) {
        await _api.submitAnswer(_recordId!, _questionId!, text,
            skipped: skipped);
      }
      if (_last) {
        _finish();
        return;
      }
      // 다음 질문
      String nextQ;
      if (_demo) {
        nextQ = demoQuestions[_step + 1];
      } else {
        final q = await _api.nextQuestion(_recordId!);
        _questionId = q['id'];
        nextQ = q['question_text'];
      }
      setState(() {
        _step++;
        _question = nextQ;
        _controller.clear();
        _submitting = false;
      });
    } on ApiException catch (e) {
      setState(() => _submitting = false);
      _showError(e.message);
    } catch (_) {
      setState(() => _submitting = false);
      _showError('서버에 연결할 수 없어요.');
    }
  }

  Future<void> _regenerate() async {
    HapticFeedback.selectionClick();
    if (_demo) {
      setState(() => _question = '오늘의 나에게 제목을 붙인다면 어떤 제목이 어울릴까요?');
      return;
    }
    try {
      final q = await _api.nextQuestion(_recordId!, regenerate: true);
      setState(() {
        _questionId = q['id'];
        _question = q['question_text'];
      });
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  void _finish() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => FilmResultScreen(
        recordId: _recordId,
        photoBytes: widget.photoBytes,
        demoUrls: widget.demoUrls,
      ),
    ));
  }

  /// 중단 확인 시트 — "회고를 그만둘까요?"
  void _confirmExit() {
    showFilmSheet(
      context,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('회고를 그만둘까요?', style: FilmText.title(context, size: 17)),
        const SizedBox(height: 6),
        Text('지금까지 쓴 답변은 저장되지 않아요.',
            style: FilmText.caption(context, size: 13)),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(
            label: '이어서 쓰기',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SecondaryButton(
            label: '그만두기',
            onPressed: () {
              Navigator.of(context).pop(); // 시트 닫기
              Navigator.of(context).pop(); // 화면 나가기
            },
          ),
        ),
      ]),
    );
  }

  void _showError(String msg) {
    setState(() {
      _loading = false;
      _submitting = false;
    });
    showFilmSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(children: [
          // ─── 상단: ‹ + 진행 표시 ───
          SizedBox(
            height: 48,
            child: Row(children: [
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _confirmExit,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.chevron_left, size: 28, color: c.ink),
                ),
              ),
              const Spacer(),
              Text('${_step + 1} / $kTotalQuestions',
                  style: FilmText.caption(context,
                      size: 13, weight: FontWeight.w500)),
              const Spacer(),
              const SizedBox(width: 48),
            ]),
          ),

          // ─── 질문 영역 ───
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Brand.amber, strokeWidth: 2))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      Row(children: [
                        const FilmMark(size: 22, color: Brand.amberTo),
                        const SizedBox(width: 8),
                        Text('오늘의 필름',
                            style: FilmText.caption(context,
                                size: 13, weight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeOut,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                                    begin: const Offset(0, 0.05),
                                    end: Offset.zero)
                                .animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          _question,
                          key: ValueKey(_question),
                          style: FilmText.display(context, size: 23)
                              .copyWith(height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 선택한 사진 미니 스트립
                      SizedBox(
                        height: 56,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.photoBytes.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: widget.photoBytes[i] != null
                                  ? Image.memory(widget.photoBytes[i]!,
                                      fit: BoxFit.cover)
                                  : Image.network(widget.demoUrls[i]!,
                                      fit: BoxFit.cover),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          // ─── 하단: 입력 + CTA ───
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(children: [
              FilmTextField(
                controller: _controller,
                hint: '편하게 적어주세요.',
                minLines: 3,
                maxLines: 5,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              // 보조 액션
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _MutedAction(
                  label: '건너뛰기',
                  onTap: _submitting ? null : () => _submit(skipped: true),
                ),
                Container(width: 1, height: 12, color: c.border),
                _MutedAction(
                  label: '질문 다시 받기',
                  onTap: _submitting ? null : _regenerate,
                ),
              ]),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: _submitting
                      ? '저장 중...'
                      : (_last ? '회고 마치기' : '다음'),
                  onPressed: _submitting ||
                          _loading ||
                          _controller.text.trim().isEmpty
                      ? null
                      : _submit,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// 하단 보조 텍스트 액션 (건너뛰기 · 질문 다시 받기).
/// 기존엔 밋밋한 텍스트라 눌러도 반응이 안 보여 탭 여부를 알기 어려웠다.
/// → 누르는 동안 앰버 알약 하이라이트 + 살짝 축소 + 앰버 텍스트로
///   탭이 확실히 인지되게 한다. (탭 순간의 햅틱은 각 콜백이 담당)
class _MutedAction extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const _MutedAction({required this.label, this.onTap});

  @override
  State<_MutedAction> createState() => _MutedActionState();
}

class _MutedActionState extends State<_MutedAction> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = FilmColors.of(context);
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: enabled ? widget.onTap : null,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 100),
        scale: _pressed ? 0.92 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color:
                _pressed ? Brand.amber.withOpacity(0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            widget.label,
            style: FilmText.caption(
              context,
              size: 13,
              color: !enabled
                  ? c.sub.withOpacity(0.4)
                  : (_pressed ? Brand.amberTo : c.sub),
              weight: _pressed ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
