import 'package:flutter/material.dart';
import 'package:loading/features/browser/ui/browser_body.dart';

class BrowserScreenT extends StatelessWidget {
  const BrowserScreenT({
    super.key,
    required this.urlController,
    required this.onPaste,
    required this.onOpen,
    required this.onDownload,
    required this.view,
  });

  final TextEditingController urlController;
  final VoidCallback onPaste;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final Widget view;

  @override
  Widget build(BuildContext context) {
    return BrowserBody(
      urlController: urlController,
      onPaste: onPaste,
      onOpen: onOpen,
      onDownload: onDownload,
      view: view,
      splitPane: true,
      layoutKey: const ValueKey('layout-browser-tablet'),
    );
  }
}
