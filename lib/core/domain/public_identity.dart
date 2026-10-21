/// Public identity only; TV pairing tokens and member invitation links are rejected.
/// QR contract v1: `iplex://user?v=1&code=<12 chars>`; the unversioned form is
/// still read so codes shown by earlier builds keep working.
const publicUserQrVersion = '1';
String? parsePublicUserCode(String raw) {
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  final isUserUri =
      uri != null &&
      uri.scheme == 'iplex' &&
      uri.host == 'user' &&
      uri.path.isEmpty;
  if (uri != null && uri.scheme == 'iplex' && !isUserUri) return null;
  String? code = value;
  if (isUserUri) {
    final params = uri.queryParameters;
    final version = params['v'];
    final allowed = params.keys.every((k) => k == 'code' || k == 'v');
    code = allowed && (version == null || version == publicUserQrVersion)
        ? params['code']
        : null;
  }
  final normalized = code?.toUpperCase();
  return normalized != null && RegExp(r'^[A-Z0-9]{12}$').hasMatch(normalized)
      ? normalized
      : null;
}

String publicUserQr(String code) =>
    'iplex://user?v=$publicUserQrVersion&code=$code';

/// Profile link QR (admin phone -> person's phone). Not a family invitation:
/// it only confirms an account for a profile the administrator already chose.
String profileLinkQr(String code) => 'iplex://profile-link?v=1&code=$code';
String? parseProfileLinkCode(String raw) {
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  String? code = value;
  if (uri != null && uri.scheme == 'iplex') {
    final params = uri.queryParameters;
    code =
        uri.host == 'profile-link' &&
            uri.path.isEmpty &&
            params.keys.every((k) => k == 'code' || k == 'v') &&
            (params['v'] == null || params['v'] == '1')
        ? params['code']
        : null;
  }
  final normalized = code?.toUpperCase();
  return normalized != null && RegExp(r'^[A-Z0-9]{8}$').hasMatch(normalized)
      ? normalized
      : null;
}
