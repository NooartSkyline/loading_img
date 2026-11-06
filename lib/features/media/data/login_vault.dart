import 'dart:convert';

import 'package:flutter/services.dart';

class LoginSecret {
  const LoginSecret({required this.user, required this.password});

  final String user;
  final String password;
}

class LoginVault {
  const LoginVault();

  static const _channel = MethodChannel('loading/login');

  Future<LoginSecret?> read(String site) async {
    try {
      final value = await _channel.invokeMethod<dynamic>('read', {
        'site': site,
      });
      if (value is! Map) return null;
      final user = value['user']?.toString().trim() ?? '';
      final password = value['password']?.toString() ?? '';
      if (user.isEmpty || password.isEmpty) return null;
      return LoginSecret(user: user, password: password);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> write(
    String site, {
    required String user,
    required String password,
  }) async {
    final name = user.trim();
    if (name.isEmpty || password.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('write', {
        'site': site,
        'user': name,
        'password': password,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

String loginCaptureScript() {
  return '''
(function() {
  if (window.__loadingCred) return;
  window.__loadingCred = true;
  var rememberedUser = '';
  function userField() {
    return document.querySelector('input[name="email"], input[name="username"], input[autocomplete="username"], input[type="email"], input[type="text"]');
  }
  function grab() {
    var userEl = userField();
    if (userEl && userEl.value) rememberedUser = userEl.value.trim();
    var passEl = document.querySelector('input[type="password"]');
    if (!rememberedUser || !passEl || !passEl.value) return;
    var bridge = window.flutter_inappwebview;
    if (!bridge || !bridge.callHandler) return;
    bridge.callHandler('loginSecret', rememberedUser, passEl.value);
  }
  document.addEventListener('change', grab, true);
  document.addEventListener('submit', grab, true);
  document.addEventListener('click', grab, true);
})();
''';
}

String loginFillScript(LoginSecret secret) {
  final user = jsonEncode(secret.user);
  final password = jsonEncode(secret.password);
  return '''
(function() {
  var user = $user;
  var pass = $password;
  function setValue(el, value) {
    if (!el || el.value) return;
    var proto = window.HTMLInputElement && window.HTMLInputElement.prototype;
    var setter = proto && Object.getOwnPropertyDescriptor(proto, 'value');
    if (setter && setter.set) setter.set.call(el, value);
    else el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function fill() {
    var passEl = document.querySelector('input[type="password"]');
    var onLogin = /login/i.test(location.pathname + location.search);
    if (!passEl && !onLogin) return true;
    var userEl = document.querySelector('input[name="email"], input[name="username"], input[autocomplete="username"], input[type="email"], input[type="text"]');
    if (userEl) setValue(userEl, user);
    if (passEl) setValue(passEl, pass);
    return Boolean(passEl && passEl.value && userEl && userEl.value);
  }
  if (fill()) return;
  var tries = 0;
  var timer = setInterval(function() {
    tries += 1;
    if (fill() || tries > 20) clearInterval(timer);
  }, 300);
})();
''';
}
