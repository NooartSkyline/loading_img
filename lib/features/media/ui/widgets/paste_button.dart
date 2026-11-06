import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool usesSystemPaste(String operatingSystem, String version) {
  if (operatingSystem != 'ios') return false;
  final major = int.tryParse(
    RegExp(r'(\d+)').firstMatch(version)?.group(1) ?? '',
  );
  return (major ?? 0) >= 16;
}

class PasteButton extends StatelessWidget {
  const PasteButton({super.key, required this.onPaste});

  final ValueChanged<String> onPaste;

  @override
  Widget build(BuildContext context) {
    if (usesSystemPaste(
      Platform.operatingSystem,
      Platform.operatingSystemVersion,
    )) {
      return SizedBox(
        width: 48,
        height: 48,
        child: _SystemPasteButton(onPaste: onPaste),
      );
    }
    return IconButton(
      onPressed: () async {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        onPaste(data?.text ?? '');
      },
      tooltip: 'วางจากคลิปบอร์ด',
      icon: const Icon(Icons.content_paste_outlined),
    );
  }
}

class _SystemPasteButton extends StatefulWidget {
  const _SystemPasteButton({required this.onPaste});

  final ValueChanged<String> onPaste;

  @override
  State<_SystemPasteButton> createState() => _SystemPasteButtonState();
}

class _SystemPasteButtonState extends State<_SystemPasteButton> {
  MethodChannel? _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: 'loading/paste',
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onPlatformViewCreated: (id) {
        final channel = MethodChannel('loading/paste/$id');
        channel.setMethodCallHandler((call) async {
          if (call.method != 'pasted') return;
          final text = call.arguments;
          if (text is String) widget.onPaste(text);
        });
        _channel = channel;
      },
    );
  }
}
