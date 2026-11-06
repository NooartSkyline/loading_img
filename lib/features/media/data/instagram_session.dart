import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:loading/features/media/data/saved_cookie.dart';

bool instagramSignedIn(String? cookie) {
  if (cookie == null || cookie.isEmpty) return false;
  for (final part in cookie.split(';')) {
    final piece = part.trim();
    if (piece.startsWith('sessionid=') && piece.length > 'sessionid='.length) {
      return true;
    }
  }
  return false;
}

abstract class InstagramSession {
  Future<String?> cookieHeader();

  Future<void> forget();
}

class WebViewInstagramSession implements InstagramSession {
  const WebViewInstagramSession({this.store = const SavedCookie('instagram')});

  final SavedCookie store;

  static final Uri _home = Uri.https('www.instagram.com', '/');

  @override
  Future<String?> cookieHeader() {
    return rememberedHeader(
      store: store,
      signedIn: instagramSignedIn,
      readLive: _readLive,
      restore: _restore,
    );
  }

  @override
  Future<void> forget() => clear();

  Future<String?> _readLive() async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri.uri(_home),
      );
      final parts = <String>[];
      var signedIn = false;
      for (final cookie in cookies) {
        final name = cookie.name.trim();
        final raw = cookie.value;
        if (raw == null) continue;
        final value = raw.toString().trim();
        if (name.isEmpty || value.isEmpty) continue;
        if (name == 'sessionid') signedIn = true;
        parts.add('$name=$value');
      }
      if (!signedIn) return null;
      return parts.join('; ');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on AssertionError {
      return null;
    }
  }

  Future<void> _restore(String header) async {
    try {
      final expires = DateTime.now()
          .add(const Duration(days: 180))
          .millisecondsSinceEpoch;
      for (final pair in cookiePairs(header)) {
        await CookieManager.instance().setCookie(
          url: WebUri.uri(_home),
          name: pair.$1,
          value: pair.$2,
          domain: '.instagram.com',
          isSecure: true,
          isHttpOnly: pair.$1 == 'sessionid',
          expiresDate: expires,
        );
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    } on AssertionError {
      return;
    }
  }

  Future<void> clear() async {
    await store.delete();
    try {
      await CookieManager.instance().deleteCookies(url: WebUri.uri(_home));
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    } on AssertionError {
      return;
    }
  }
}
