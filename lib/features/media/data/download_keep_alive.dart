import 'package:flutter/services.dart';

class DownloadKeepAlive {
  DownloadKeepAlive({Future<void> Function(String method)? invoke})
    : _invoke = invoke ?? _platform;

  static const _channel = MethodChannel('loading/keep_alive');

  final Future<void> Function(String method) _invoke;
  int _holds = 0;

  Future<void> acquire() async {
    _holds += 1;
    if (_holds > 1) return;
    await _invoke('acquire');
  }

  Future<void> release() async {
    if (_holds == 0) return;
    _holds -= 1;
    if (_holds > 0) return;
    await _invoke('release');
  }

  static Future<void> _platform(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // เครื่องที่ไม่ใช่มือถือไม่มีตัวกันหลุด โหลดในหน้าจอยังทำงานได้
    } on PlatformException {
      // เปิดบริการกันหลุดไม่ได้ โหลดต่อในขณะที่แอปอยู่หน้าจอ
    }
  }
}
