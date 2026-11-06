import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:loading/core/responsive.dart';
import 'package:loading/features/browser/bloc/browser_cubit.dart';
import 'package:loading/features/browser/ui/browser_screen_m.dart';
import 'package:loading/features/browser/ui/browser_screen_t.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final TextEditingController _urlController = TextEditingController();
  InAppWebViewController? _controller;
  String? _pendingUrl;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _paste(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      context.read<BrowserCubit>().fail('คลิปบอร์ดว่าง');
      return;
    }
    _urlController.text = text;
    _urlController.selection = TextSelection.collapsed(
      offset: _urlController.text.length,
    );
  }

  Future<void> _open() async {
    final cubit = context.read<BrowserCubit>();
    if (cubit.state.isBusy) return;
    final raw = _urlController.text.trim();
    final withScheme = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      cubit.fail('ลิงก์ต้องขึ้นต้นด้วย http หรือ https');
      return;
    }
    final url = uri.toString();
    _urlController.text = url;
    _pendingUrl = url;
    cubit.openPage();
    final controller = _controller;
    if (controller != null) {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }
  }

  Future<void> _download() async {
    final cubit = context.read<BrowserCubit>();
    final page = _urlController.text.trim();
    final controller = _controller;
    final cookie = controller == null
        ? null
        : await _cookie(controller, page, cubit.state.selected?.url);
    final userAgent = controller == null ? null : await _userAgent(controller);
    if (!mounted) return;
    await cubit.download(
      referer: page.startsWith('http') ? page : 'https://$page',
      cookie: cookie,
      userAgent: userAgent,
    );
  }

  Future<void> _rememberAgent(InAppWebViewController controller) async {
    final agent = await _userAgent(controller);
    if (!mounted) return;
    context.read<BrowserCubit>().setUserAgent(agent);
  }

  Future<String?> _userAgent(InAppWebViewController controller) async {
    final value = await controller.evaluateJavascript(
      source: 'navigator.userAgent',
    );
    if (value is! String) return null;
    var agent = value.trim();
    if (agent.length >= 2 && agent.startsWith('"') && agent.endsWith('"')) {
      agent = agent.substring(1, agent.length - 1);
    }
    if (agent.isEmpty || agent == 'null') return null;
    return agent;
  }

  Future<String?> _cookie(
    InAppWebViewController controller,
    String page,
    String? streamUrl,
  ) async {
    final values = <String>[];
    for (final url in [page, streamUrl]) {
      if (url == null || !url.startsWith('http')) continue;
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(url),
        webViewController: controller,
      );
      for (final cookie in cookies) {
        values.add('${cookie.name}=${cookie.value}');
      }
    }
    if (values.isEmpty) return null;
    return values.toSet().join('; ');
  }

  @override
  Widget build(BuildContext context) {
    final view = BlocBuilder<BrowserCubit, BrowserState>(
      buildWhen: (previous, next) => previous.opened != next.opened,
      builder: (context, state) {
        if (!state.opened) return const SizedBox.shrink();
        return InAppWebView(
          key: const ValueKey('page-view'),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: true,
            allowsInlineMediaPlayback: true,
            thirdPartyCookiesEnabled: true,
            sharedCookiesEnabled: true,
            useOnLoadResource: true,
          ),
          onWebViewCreated: (controller) {
            _controller = controller;
            unawaited(_rememberAgent(controller));
            final pending = _pendingUrl;
            if (pending != null) {
              controller.loadUrl(urlRequest: URLRequest(url: WebUri(pending)));
            }
          },
          onLoadResource: (controller, resource) {
            final url = resource.url?.toString();
            if (url == null || !mounted) return;
            context.read<BrowserCubit>().addResource(
              url,
              page: _urlController.text,
            );
          },
          onUpdateVisitedHistory: (controller, url, androidIsReload) {
            final next = url?.toString();
            if (next == null || !mounted) return;
            _urlController.text = next;
          },
        );
      },
    );
    return Responsive(
      mobile: BrowserScreenM(
        urlController: _urlController,
        onPaste: _paste,
        onOpen: _open,
        onDownload: _download,
        view: view,
      ),
      tablet: BrowserScreenT(
        urlController: _urlController,
        onPaste: _paste,
        onOpen: _open,
        onDownload: _download,
        view: view,
      ),
    );
  }
}
