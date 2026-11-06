import 'package:flutter_test/flutter_test.dart';
import 'package:loading/features/media/ui/widgets/paste_button.dart';

void main() {
  test('ios 16 and newer paste without asking', () {
    expect(usesSystemPaste('ios', 'Version 16.0 (Build 20A362)'), isTrue);
    expect(usesSystemPaste('ios', 'Version 26.7.2 (Build 23A)'), isTrue);
    expect(usesSystemPaste('ios', 'Version 15.5 (Build 19F77)'), isFalse);
    expect(usesSystemPaste('android', '14'), isFalse);
  });
}
