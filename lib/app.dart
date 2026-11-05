import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading/core/app_theme.dart';
import 'package:loading/features/browser/bloc/browser_cubit.dart';
import 'package:loading/features/browser/data/stream_saver.dart';
import 'package:loading/features/media/bloc/media_bloc.dart';
import 'package:loading/features/media/data/gallery_store.dart';
import 'package:loading/features/media/data/media_repository.dart';
import 'package:loading/features/shell/root_screen.dart';

class LoadingApp extends StatelessWidget {
  const LoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (_) => MediaRepository(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (context) => MediaBloc(context.read<MediaRepository>())),
          BlocProvider(create: (_) => BrowserCubit(StreamSaver(), const GalleryStore())),
        ],
        child: MaterialApp(
          title: 'โหลดสื่อ',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const RootScreen(),
        ),
      ),
    );
  }
}
