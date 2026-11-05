import 'package:flutter/material.dart';
import 'package:loading/features/media/ui/home_body.dart';

class HomeScreenT extends StatelessWidget {
  const HomeScreenT({
    super.key,
    required this.urlController,
    required this.onPaste,
  });

  final TextEditingController urlController;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return HomeBody(
      urlController: urlController,
      onPaste: onPaste,
      splitPane: true,
      gridColumns: 3,
      layoutKey: const ValueKey('layout-tablet'),
    );
  }
}
