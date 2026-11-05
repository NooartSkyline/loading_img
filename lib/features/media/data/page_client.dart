import 'package:dio/dio.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/data/browser_headers.dart';

class PageClient {
  PageClient({Dio? dio})
      : dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 25),
                followRedirects: true,
                maxRedirects: 8,
              ),
            );

  final Dio dio;

  Future<String> getHtml(Uri uri) async {
    try {
      final response = await dio.get<String>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          headers: browserHeaders(referer: uri.origin),
          validateStatus: (status) => status != null && status >= 200 && status < 300,
        ),
      );
      final body = response.data;
      if (body == null || body.trim().isEmpty) {
        throw const AppException('หน้านี้ตอบกลับว่าง');
      }
      return body;
    } on DioException catch (error) {
      throw asAppException(error);
    }
  }

  Future<Uri> resolveRedirect(Uri uri) async {
    try {
      final response = await dio.get<String>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          headers: browserHeaders(referer: uri.origin),
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );
      return response.realUri;
    } on DioException catch (error) {
      throw asAppException(error);
    }
  }
}
