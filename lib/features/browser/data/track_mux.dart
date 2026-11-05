import 'package:flutter/services.dart';
import 'package:loading/core/app_exception.dart';

class TrackMux {
  const TrackMux();

  static const _channel = MethodChannel('loading/mux');

  Future<void> combine({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    try {
      await _channel.invokeMethod<void>('combine', {
        'video': videoPath,
        'audio': audioPath,
        'output': outputPath,
      });
    } on MissingPluginException {
      throw const AppException('เครื่องนี้ยังรวมภาพกับเสียงไม่ได้');
    } on PlatformException catch (error) {
      final message = error.message;
      throw AppException(
        message == null || message.isEmpty ? 'รวมภาพกับเสียงไม่ได้' : message,
      );
    }
  }
}
