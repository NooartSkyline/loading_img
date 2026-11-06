import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:loading/features/media/data/saved_cookie.dart';

bool facebookSignedIn(String? cookie) {
  if (cookie == null || cookie.isEmpty) return false;
  var user = false;
  var token = false;
  for (final part in cookie.split(';')) {
    final piece = part.trim();
    if (piece.startsWith('c_user=') && piece.length > 'c_user='.length) {
      user = true;
    }
    if (piece.startsWith('xs=') && piece.length > 'xs='.length) token = true;
  }
  return user && token;
}

abstract class FacebookSession {
  Future<String?> cookieHeader();

  Future<void> forget();
}

class WebViewFacebookSession implements FacebookSession {
  const WebViewFacebookSession({this.store = const SavedCookie('facebook')});

  final SavedCookie store;

  static final List<Uri> _homes = [
    Uri.https('www.facebook.com', '/'),
    Uri.https('m.facebook.com', '/'),
    Uri.https('mbasic.facebook.com', '/'),
  ];

  @override
  Future<String?> cookieHeader() {
    return rememberedHeader(
      store: store,
      signedIn: facebookSignedIn,
      readLive: _readLive,
      restore: _restore,
    );
  }

  @override
  Future<void> forget() => clear();

  Future<String?> _readLive() async {
    try {
      final parts = <String>[];
      final seen = <String>{};
      for (final home in _homes) {
        final cookies = await CookieManager.instance().getCookies(
          url: WebUri.uri(home),
        );
        for (final cookie in cookies) {
          final name = cookie.name.trim();
          final raw = cookie.value;
          if (raw == null) continue;
          final value = raw.toString().trim();
          if (name.isEmpty || value.isEmpty || !seen.add(name)) continue;
          parts.add('$name=$value');
        }
      }
      final header = parts.join('; ');
      if (!facebookSignedIn(header)) return null;
      return header;
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
      for (final home in _homes) {
        for (final pair in cookiePairs(header)) {
          await CookieManager.instance().setCookie(
            url: WebUri.uri(home),
            name: pair.$1,
            value: pair.$2,
            domain: '.facebook.com',
            isSecure: true,
            isHttpOnly: pair.$1 == 'c_user' || pair.$1 == 'xs',
            expiresDate: expires,
          );
        }
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
      for (final home in _homes) {
        await CookieManager.instance().deleteCookies(url: WebUri.uri(home));
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    } on AssertionError {
      return;
    }
  }
}
