import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class SavedCookie {
  const SavedCookie(this.name, {this.directory});

  final String name;
  final Future<Directory> Function()? directory;

  Future<String?> read() async {
    try {
      final file = await _file();
      if (file == null || !file.existsSync()) return null;
      final text = (await file.readAsString()).trim();
      if (text.isEmpty) return null;
      return text;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(String header) async {
    final file = await _file();
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(header, flush: true);
  }

  Future<void> delete() async {
    try {
      final file = await _file();
      if (file != null && file.existsSync()) await file.delete();
    } on FileSystemException {
      return;
    }
  }

  Future<File?> _file() async {
    try {
      final root = directory == null
          ? await getApplicationSupportDirectory()
          : await directory!();
      return File('${root.path}${Platform.pathSeparator}session-$name.txt');
    } on MissingPluginException {
      return null;
    } on FlutterError {
      return null;
    }
  }
}

List<(String name, String value)> cookiePairs(String header) {
  final pairs = <(String, String)>[];
  for (final part in header.split(';')) {
    final piece = part.trim();
    final split = piece.indexOf('=');
    if (split <= 0) continue;
    final name = piece.substring(0, split).trim();
    final value = piece.substring(split + 1).trim();
    if (name.isEmpty || value.isEmpty) continue;
    pairs.add((name, value));
  }
  return pairs;
}

Future<String?> rememberedHeader({
  required SavedCookie store,
  required bool Function(String? header) signedIn,
  required Future<String?> Function() readLive,
  required Future<void> Function(String header) restore,
}) async {
  final live = await readLive();
  if (signedIn(live)) {
    await store.write(live!);
    return live;
  }
  final saved = await store.read();
  if (!signedIn(saved)) return null;
  await restore(saved!);
  return saved;
}
