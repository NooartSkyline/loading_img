import 'package:flutter_test/flutter_test.dart';
import 'package:loading/features/media/data/download_keep_alive.dart';

void main() {
  test('keep alive stays held until the last download finishes', () async {
    final calls = <String>[];
    final keepAlive = DownloadKeepAlive(
      invoke: (method) async => calls.add(method),
    );

    await keepAlive.acquire();
    await keepAlive.acquire();
    await keepAlive.release();

    expect(calls, ['acquire']);

    await keepAlive.release();
    await keepAlive.release();

    expect(calls, ['acquire', 'release']);
  });
}
