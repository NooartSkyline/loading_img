import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loading/features/media/data/facebook_session.dart';
import 'package:loading/features/media/data/instagram_session.dart';
import 'package:loading/features/media/data/saved_cookie.dart';

void main() {
  test('a saved login is used after the web view forgets it', () async {
    final root = await Directory.systemTemp.createTemp('saved-cookie');
    final store = SavedCookie('facebook', directory: () async => root);
    await store.write('c_user=1; xs=token');
    String? restored;

    final header = await rememberedHeader(
      store: store,
      signedIn: facebookSignedIn,
      readLive: () async => null,
      restore: (value) async => restored = value,
    );

    expect(header, 'c_user=1; xs=token');
    expect(restored, header);
    await root.delete(recursive: true);
  });

  test('a live login replaces the saved one', () async {
    final root = await Directory.systemTemp.createTemp('saved-cookie');
    final store = SavedCookie('instagram', directory: () async => root);
    await store.write('sessionid=old');

    final header = await rememberedHeader(
      store: store,
      signedIn: instagramSignedIn,
      readLive: () async => 'sessionid=new',
      restore: (_) async => fail('the live session should not be restored'),
    );

    expect(header, 'sessionid=new');
    expect(await store.read(), 'sessionid=new');
    await root.delete(recursive: true);
  });

  test('forgetting a login removes the saved cookie', () async {
    final root = await Directory.systemTemp.createTemp('saved-cookie');
    final store = SavedCookie('facebook', directory: () async => root);
    await store.write('c_user=1; xs=token');

    await WebViewFacebookSession(store: store).forget();

    expect(await store.read(), isNull);
    await root.delete(recursive: true);
  });
}
