import 'dart:io';

import 'package:gal/gal.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/model/media_kind.dart';

class GalleryStore {
  const GalleryStore();

  static const album = 'โหลดสื่อ';

  Future<void> save({required File file, required MediaKind kind}) async {
    final alreadyAllowed = await Gal.hasAccess(toAlbum: true);
    final allowed = alreadyAllowed || await Gal.requestAccess(toAlbum: true);
    if (!allowed) {
      throw const AppException(
        'ยังไม่ได้สิทธิ์บันทึกลงคลังภาพ เปิดสิทธิ์รูปภาพให้แอปแล้วลองใหม่',
      );
    }
    try {
      if (kind == MediaKind.image) {
        await Gal.putImage(file.path, album: album);
      } else {
        await Gal.putVideo(file.path, album: album);
      }
    } on GalException catch (error) {
      throw AppException(_message(error.type));
    }
  }

  String _message(GalExceptionType type) {
    switch (type) {
      case GalExceptionType.accessDenied:
        return 'ยังไม่ได้สิทธิ์บันทึกลงคลังภาพ เปิดสิทธิ์รูปภาพให้แอปแล้วลองใหม่';
      case GalExceptionType.notEnoughSpace:
        return 'พื้นที่เครื่องไม่พอสำหรับไฟล์นี้';
      case GalExceptionType.notSupportedFormat:
        return 'คลังภาพไม่รองรับนามสกุลนี้';
      case GalExceptionType.unexpected:
        return 'บันทึกลงคลังภาพไม่ได้';
    }
  }
}
