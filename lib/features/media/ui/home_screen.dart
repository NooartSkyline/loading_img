import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading/core/responsive.dart';
import 'package:loading/features/media/bloc/media_bloc.dart';
import 'package:loading/features/media/bloc/media_event.dart';
import 'package:loading/features/media/ui/home_screen_m.dart';
import 'package:loading/features/media/ui/home_screen_t.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      context.read<MediaBloc>().add(const NoticeRequested('คลิปบอร์ดว่าง'));
      return;
    }
    _urlController.text = text;
    _urlController.selection = TextSelection.collapsed(offset: _urlController.text.length);
  }

  @override
  Widget build(BuildContext context) {
    return Responsive(
      mobile: HomeScreenM(urlController: _urlController, onPaste: _paste),
      tablet: HomeScreenT(urlController: _urlController, onPaste: _paste),
    );
  }
}
