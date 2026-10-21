import 'package:flutter/services.dart';

import '../domain/models.dart';

/// Release builds supply an approved installation URL. Until then the user-
/// approved provisional message is shared, never a fabricated store address.
class AppSharing {
  static const channel = MethodChannel('iplex/app_sharing');
  static const installationUrl = String.fromEnvironment('IPLEX_INSTALL_URL');
  static String message(
    String title,
    String provisional, {
    String url = installationUrl,
  }) {
    final uri = Uri.tryParse(url);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? '$title\n$uri'
        : provisional;
  }

  static Future<void> share(String text) async {
    try {
      await channel.invokeMethod<void>('share', {'text': text});
    } on MissingPluginException {
      throw const AppFailure('share-unavailable');
    } on PlatformException {
      throw const AppFailure('share-unavailable');
    }
  }
}
