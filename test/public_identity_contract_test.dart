import 'package:aliens_syndicate_iplex_control/core/domain/public_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user QR v1 round-trips and stays distinct from the TV pairing QR', () {
    const code = 'K7M4P9R2T6X8';
    expect(publicUserQr(code), 'iplex://user?v=1&code=$code');
    expect(parsePublicUserCode(publicUserQr(code)), code);
    expect(parsePublicUserCode('iplex://user?code=$code'), code);
    expect(parsePublicUserCode(' k7m4p9r2t6x8 '), code);
  });

  test(
    'rejects TV tokens, unknown versions, extra fields and invite links',
    () {
      for (final raw in [
        'iplex://pair?token=${'a' * 64}',
        'iplex://user?v=2&code=K7M4P9R2T6X8',
        'iplex://user?v=1&code=K7M4P9R2T6X8&familyId=abc',
        'https://iplex.app/join?code=K7M4P9R2T6X8',
        'K7M4P9R2T6X',
        '',
      ]) {
        expect(parsePublicUserCode(raw), isNull, reason: raw);
      }
    },
  );
}
