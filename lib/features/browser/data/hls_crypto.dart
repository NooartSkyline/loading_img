import 'dart:typed_data';

import 'package:loading/core/app_exception.dart';
import 'package:pointycastle/export.dart';

Uint8List decryptAes128Cbc({
  required Uint8List data,
  required Uint8List key,
  required Uint8List iv,
}) {
  if (key.length != 16 || iv.length != 16) {
    throw const AppException('คีย์ของสตรีมนี้ใช้ไม่ได้');
  }
  if (data.isEmpty || data.length % 16 != 0) {
    throw const AppException('ชิ้นส่วนที่เข้ารหัสไม่ครบช่วง');
  }
  final cipher = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(key), iv));
  final output = Uint8List(data.length);
  for (var offset = 0; offset < data.length; offset += 16) {
    cipher.processBlock(data, offset, output, offset);
  }
  final pad = output.last;
  if (pad == 0 || pad > 16) throw const AppException('ถอดรหัสสตรีมไม่ได้');
  for (var index = 0; index < pad; index++) {
    if (output[output.length - 1 - index] != pad) {
      throw const AppException('ถอดรหัสสตรีมไม่ได้');
    }
  }
  return Uint8List.sublistView(output, 0, output.length - pad);
}

Uint8List ivForSequence(int sequence) {
  final iv = Uint8List(16);
  var value = sequence;
  for (var index = 15; index >= 0 && value > 0; index--) {
    iv[index] = value & 0xff;
    value >>= 8;
  }
  return iv;
}
