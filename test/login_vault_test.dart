import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loading/features/media/data/login_vault.dart';

void main() {
  test('saved password with a quote stays inside the script', () {
    const secret = LoginSecret(user: 'me', password: 'p"ass');
    final script = loginFillScript(secret);

    expect(script, contains(jsonEncode(secret.password)));
    expect(script, contains(jsonEncode(secret.user)));
    expect(script.contains('pass = p"ass'), isFalse);
  });

  test(
    'capture script remembers the name from the page before the password',
    () {
      expect(loginCaptureScript(), contains('rememberedUser'));
    },
  );
}
