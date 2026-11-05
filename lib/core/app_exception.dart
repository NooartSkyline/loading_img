import 'package:dio/dio.dart';

class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

AppException asAppException(Object error) {
  if (error is AppException) return error;
  if (error is DioException) return AppException(describeDio(error));
  if (error is FormatException) {
    return const AppException('สตรีมนี้ไม่ใช่รายการวิดีโอที่ใช้โหลดได้');
  }
  return AppException('ดำเนินการไม่สำเร็จ: $error');
}

String describeDio(DioException error) {
  if (error.type == DioExceptionType.cancel) return 'ยกเลิกการโหลดแล้ว';
  final code = error.response?.statusCode;
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'หมดเวลารอการเชื่อมต่อ';
    case DioExceptionType.connectionError:
      return 'เชื่อมต่ออินเทอร์เน็ตไม่ได้';
    case DioExceptionType.badResponse:
      return 'เซิร์ฟเวอร์ตอบกลับรหัส ${code ?? '-'}';
    case DioExceptionType.cancel:
      return 'ยกเลิกการโหลดแล้ว';
    case DioExceptionType.badCertificate:
      return 'ใบรับรองของเซิร์ฟเวอร์ไม่ถูกต้อง';
    case DioExceptionType.transformTimeout:
    case DioExceptionType.unknown:
      return error.message ?? 'โหลดข้อมูลไม่สำเร็จ';
  }
}
