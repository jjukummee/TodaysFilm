// 백엔드 API 클라이언트.
//
// backend/README.md 의 API와 1:1 대응.
// 로그인 전(또는 서버 미실행)에는 각 화면이 데모 데이터로 동작하므로
// 디자이너/개발자가 서버 없이도 UI를 확인할 수 있다.
//
// 안정성:
// - 모든 요청에 타임아웃 (LLM 엔드포인트는 넉넉하게)
// - 401 응답 시 토큰 자동 폐기 (만료된 세션 → 데모 모드로 자연 복귀)
// - 네트워크 예외를 ApiException 으로 통일 (화면에서 한 가지만 처리)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  /// 백엔드 주소.
  /// - iOS 시뮬레이터: http://localhost:8000
  /// - Android 에뮬레이터: http://10.0.2.2:8000 (자동 처리됨)
  /// - 실기기: PC의 LAN IP
  static String baseUrl =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:8000'
          : 'http://localhost:8000';

  /// 백엔드가 주는 상대 경로(/photos/... 등)를 절대 URL로 변환.
  static String resolveUrl(String url) =>
      url.startsWith('http') ? url : '$baseUrl$url';

  static const _timeout = Duration(seconds: 15);
  static const _llmTimeout = Duration(seconds: 90); // LLM 생성은 오래 걸릴 수 있음

  String? _token;
  bool get isLoggedIn => _token != null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// 인증이 필요한 이미지 로딩용 (Image.network 의 headers 파라미터에 전달)
  Map<String, String> get imageHeaders =>
      {if (_token != null) 'Authorization': 'Bearer $_token'};

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token');
  }

  Future<void> _saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
  }

  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }

  // ─── 공통 요청 래퍼 ───────────────────────────────
  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    Object? body,
    int expected = 200,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    http.Response res;
    try {
      final future = switch (method) {
        'GET' => http.get(uri, headers: _headers),
        'POST' => http.post(uri, headers: _headers, body: jsonEncode(body ?? {})),
        'PATCH' =>
          http.patch(uri, headers: _headers, body: jsonEncode(body ?? {})),
        'DELETE' => http.delete(uri, headers: _headers),
        _ => throw ArgumentError(method),
      };
      res = await future.timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw ApiException(0, '응답이 늦어지고 있어요. 잠시 후 다시 시도해 주세요.');
    } on SocketException {
      throw ApiException(0, '서버에 연결할 수 없어요. 네트워크를 확인해 주세요.');
    }
    _check(res, expected);
    if (res.body.isEmpty) return {};
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
  }

  // ─── 인증 ───────────────────────────────────────
  Future<void> signup(String email, String password, String nickname) async {
    final body = await _requestJson('POST', '/auth/signup',
        body: {'email': email, 'password': password, 'nickname': nickname},
        expected: 201);
    await _saveToken(body['access_token']);
  }

  Future<void> login(String email, String password) async {
    final body = await _requestJson('POST', '/auth/login',
        body: {'email': email, 'password': password});
    await _saveToken(body['access_token']);
  }

  Future<Map<String, dynamic>> me() => _requestJson('GET', '/auth/me');

  Future<Map<String, dynamic>> myStats() =>
      _requestJson('GET', '/auth/me/stats');

  Future<void> deleteAccount() async {
    await _requestJson('DELETE', '/auth/me', expected: 204);
    await logout();
  }

  // ─── 사진 업로드 ─────────────────────────────────
  Future<List<Map<String, dynamic>>> uploadPhotos(
      List<Uint8List> images) async {
    final req =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/photos/upload'));
    req.headers['Authorization'] = 'Bearer $_token';
    for (var i = 0; i < images.length; i++) {
      req.files.add(http.MultipartFile.fromBytes('files', images[i],
          filename: 'photo_$i.jpg'));
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await req.send())
          .timeout(const Duration(seconds: 60)); // 사진 여러 장 업로드 고려
    } on TimeoutException {
      throw ApiException(0, '업로드가 늦어지고 있어요. 네트워크를 확인해 주세요.');
    } on SocketException {
      throw ApiException(0, '서버에 연결할 수 없어요. 네트워크를 확인해 주세요.');
    }
    _check(res, 201);
    return (jsonDecode(utf8.decode(res.bodyBytes)) as List)
        .cast<Map<String, dynamic>>();
  }

  // ─── 회고 플로우 ─────────────────────────────────
  Future<Map<String, dynamic>> createRecord(
          List<String> photoIds, String mainPhotoId) =>
      _requestJson('POST', '/records',
          body: {'photo_ids': photoIds, 'main_photo_id': mainPhotoId},
          expected: 201);

  Future<Map<String, dynamic>> nextQuestion(String recordId,
          {bool regenerate = false}) =>
      _requestJson('POST', '/records/$recordId/questions',
          body: {'regenerate': regenerate}, timeout: _llmTimeout);

  Future<void> submitAnswer(String recordId, String questionId, String text,
          {bool skipped = false}) =>
      _requestJson('POST', '/records/$recordId/answers',
          body: {
            'question_id': questionId,
            'answer_text': text,
            'skipped': skipped
          },
          expected: 201);

  Future<Map<String, dynamic>> generateFilm(String recordId) => _requestJson(
      'POST', '/records/$recordId/film',
      timeout: _llmTimeout);

  // ─── 아카이브 ────────────────────────────────────
  Future<Map<String, dynamic>> monthCalendar(int year, int month) =>
      _requestJson('GET', '/archive/calendar?year=$year&month=$month');

  Future<Map<String, dynamic>> recordDetail(String id) =>
      _requestJson('GET', '/records/$id');

  // ─── 응답 검증 ───────────────────────────────────
  void _check(http.Response res, int expected) {
    if (res.statusCode == 401 && _token != null) {
      // 토큰 만료 → 세션 폐기 (다음 화면부터 데모/로그인 유도)
      logout();
    }
    if (res.statusCode != expected) {
      final detail = () {
        try {
          return jsonDecode(utf8.decode(res.bodyBytes))['detail'];
        } catch (_) {
          return '오류가 발생했어요 (${res.statusCode})';
        }
      }();
      throw ApiException(res.statusCode, '$detail');
    }
  }
}

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}
