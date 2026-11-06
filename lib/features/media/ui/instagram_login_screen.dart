import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:loading/core/app_colors.dart';
import 'package:loading/features/media/data/browser_headers.dart';
import 'package:loading/features/media/data/facebook_session.dart';
import 'package:loading/features/media/data/instagram_session.dart';

class InstagramLoginScreen {
  const InstagramLoginScreen._();

  static Future<bool> open(BuildContext context) {
    return _CookieLoginScreen.open(
      context,
      title: 'ล็อกอิน Instagram',
      startUrl: 'https://www.instagram.com/accounts/login/',
      viewKey: 'instagram-login',
      prepare: const WebViewInstagramSession().clear,
      signedIn: () async {
        final header = await const WebViewInstagramSession().cookieHeader();
        return instagramSignedIn(header);
      },
      failure: 'เปิดหน้าล็อกอิน Instagram ไม่ได้',
    );
  }
}

class FacebookLoginScreen {
  const FacebookLoginScreen._();

  static Future<bool> open(BuildContext context) {
    return _CookieLoginScreen.open(
      context,
      title: 'ล็อกอิน Facebook',
      startUrl: 'https://m.facebook.com/login.php',
      viewKey: 'facebook-login',
      prepare: const WebViewFacebookSession().clear,
      signedIn: () async {
        final header = await const WebViewFacebookSession().cookieHeader();
        return facebookSignedIn(header);
      },
      failure: 'เปิดหน้าล็อกอิน Facebook ไม่ได้',
    );
  }
}

class _CookieLoginScreen extends StatefulWidget {
  const _CookieLoginScreen({
    required this.title,
    required this.startUrl,
    required this.viewKey,
    required this.prepare,
    required this.signedIn,
    required this.failure,
  });

  final String title;
  final String startUrl;
  final String viewKey;
  final Future<void> Function() prepare;
  final Future<bool> Function() signedIn;
  final String failure;

  static Future<bool> open(
    BuildContext context, {
    required String title,
    required String startUrl,
    required String viewKey,
    required Future<void> Function() prepare,
    required Future<bool> Function() signedIn,
    required String failure,
  }) {
    return Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => _CookieLoginScreen(
              title: title,
              startUrl: startUrl,
              viewKey: viewKey,
              prepare: prepare,
              signedIn: signedIn,
              failure: failure,
            ),
          ),
        )
        .then((value) => value ?? false);
  }

  @override
  State<_CookieLoginScreen> createState() => _CookieLoginScreenState();
}

class _CookieLoginScreenState extends State<_CookieLoginScreen> {
  var _ready = false;
  var _closed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    await widget.prepare();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _finishIfSignedIn() async {
    if (_closed || !mounted) return;
    final signedIn = await widget.signedIn();
    if (!signedIn || !mounted || _closed) return;
    _closed = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title)),
      body: _ready
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Material(
                    color: AppColors.danger.withValues(alpha: 0.14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ),
                Expanded(
                  child: InAppWebView(
                    key: ValueKey(widget.viewKey),
                    initialUrlRequest: URLRequest(url: WebUri(widget.startUrl)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      userAgent: kBrowserUserAgent,
                      thirdPartyCookiesEnabled: true,
                      sharedCookiesEnabled: true,
                    ),
                    onLoadStop: (controller, url) {
                      unawaited(_finishIfSignedIn());
                    },
                    onUpdateVisitedHistory: (controller, url, androidIsReload) {
                      unawaited(_finishIfSignedIn());
                    },
                    onReceivedError: (controller, request, error) {
                      if (request.isForMainFrame != true || !mounted) return;
                      setState(() => _error = widget.failure);
                    },
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
