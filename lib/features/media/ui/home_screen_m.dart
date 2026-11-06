import 'package:flutter/material.dart';
import 'package:loading/features/media/ui/home_body.dart';

class HomeScreenM extends StatelessWidget {
  const HomeScreenM({
    super.key,
    required this.urlController,
    required this.onPaste,
  });

  final TextEditingController urlController;
  final ValueChanged<String> onPaste;

  @override
  Widget build(BuildContext context) {
    return HomeBody(
      urlController: urlController,
      onPaste: onPaste,
      splitPane: false,
      gridColumns: 2,
      layoutKey: const ValueKey('layout-phone'),
    );
  }
}
