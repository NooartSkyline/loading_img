import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/data/browser_headers.dart';
import 'package:loading/features/media/data/instagram_parser.dart';
import 'package:loading/features/media/model/resolved_post.dart';

abstract class InstagramApi {
  Future<ResolvedPost> load(Uri page, {required String cookie});
}

class DioInstagramApi implements InstagramApi {
  DioInstagramApi({Dio? dio, InstagramParser? parser})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 25),
            ),
          ),
      _parser = parser ?? InstagramParser();

  final Dio _dio;
  final InstagramParser _parser;

  @override
  Future<ResolvedPost> load(Uri page, {required String cookie}) async {
    final code = InstagramParser.shortcodeOf(page);
    if (code == null) {
      throw const AppException('ลิงก์ Instagram ไม่ใช่โพสต์หรือรีล');
    }
    final id = InstagramParser.mediaIdOf(code);
    final headers = browserHeaders(referer: 'https://www.instagram.com/');
    headers['X-IG-App-ID'] = '936619743392459';
    headers['X-Requested-With'] = 'XMLHttpRequest';
    headers['Cookie'] = cookie;
    final csrf = _csrf(cookie);
    if (csrf != null) headers['X-CSRFToken'] = csrf;
    try {
      final response = await _dio.get<String>(
        'https://www.instagram.com/api/v1/media/$id/info/',
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          headers: headers,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return _parser.postFromMediaInfo(_json(response), page);
    } on DioException catch (error) {
      throw asAppException(error);
    }
  }

  Map<String, dynamic> _json(Response<String> response) {
    final status = response.statusCode ?? 0;
    if (status == 301 || status == 302 || status == 401 || status == 403) {
      throw const InstagramLoginRequired();
    }
    final body = response.data?.trim() ?? '';
    if (body.isEmpty || !body.startsWith('{')) {
      throw const InstagramLoginRequired();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const InstagramLoginRequired();
    }
    if (decoded is! Map) throw const InstagramLoginRequired();
    final json = Map<String, dynamic>.from(decoded);
    final message = json['message'];
    if (message == 'login_required' || message == 'checkpoint_required') {
      throw const InstagramLoginRequired();
    }
    if (status == 404) {
      throw const AppException('ไม่พบโพสต์ Instagram นี้');
    }
    if (status >= 400) {
      throw AppException('Instagram ตอบกลับรหัส $status');
    }
    return json;
  }

  String? _csrf(String cookie) {
    for (final part in cookie.split(';')) {
      final piece = part.trim();
      if (!piece.startsWith('csrftoken=')) continue;
      final value = piece.substring('csrftoken='.length);
      if (value.isNotEmpty) return value;
    }
    return null;
  }
}
