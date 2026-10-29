import '../../domain/enums/legal_document_type.dart';

/// Execution environment for resolving legal document endpoints.
enum LegalEnvironment {
  development,
  staging,
  production;

  static LegalEnvironment current() {
    const env = String.fromEnvironment('ENVIRONMENT', defaultValue: '');
    if (env.toLowerCase() == 'staging' || env.toLowerCase() == 'homologation') {
      return LegalEnvironment.staging;
    }
    const emulator = bool.fromEnvironment('USE_EMULATORS');
    if (emulator ||
        env.toLowerCase() == 'development' ||
        env.toLowerCase() == 'dev') {
      return LegalEnvironment.development;
    }
    return LegalEnvironment.production;
  }
}

/// Centralized resolver and security validator for legal documents in iPlex.
class LegalDocumentUrlResolver {
  const LegalDocumentUrlResolver({
    this.environment = LegalEnvironment.production,
    this.customTermsUrl = const String.fromEnvironment('TERMS_URL'),
    this.customPrivacyUrl = const String.fromEnvironment('PRIVACY_URL'),
  });

  final LegalEnvironment environment;
  final String customTermsUrl;
  final String customPrivacyUrl;

  /// Site that hosts the official Terms of Use and Privacy Policy.
  static const String legalBaseHost = 'aliens-syndicate-docs.web.app';
  static const String devLocalHost = '127.0.0.1';
  static const String devAndroidHost = '10.0.2.2';

  /// Whitelisted domains permitted for in-app legal WebView display.
  static const Set<String> authorizedDomains = {
    legalBaseHost,
    'iplex-2c8fc.web.app',
    'iplex-2c8fc.firebaseapp.com',
    'iplex.app',
    'staging.iplex.app',
    'dev.iplex.app',
    'iplex-staging.web.app',
    'iplex-dev.web.app',
  };

  /// Resolves the canonical public URL for a given legal document type.
  Uri resolve(LegalDocumentType type, {String? languageCode}) {
    // 1. Check compile-time environment overrides
    final customUrl = type == LegalDocumentType.termsOfUse
        ? customTermsUrl.trim()
        : customPrivacyUrl.trim();

    if (customUrl.isNotEmpty) {
      final parsed = Uri.tryParse(customUrl);
      if (parsed != null && isAllowedLegalUrl(parsed)) {
        return _applyLocale(parsed, languageCode);
      }
    }

    // 2. Official pages, published on the Aliens Syndicate site (Firebase
    // Hosting, project aliens-syndicate-docs) in every environment: there is
    // no separate staging or local copy of the legal documents.
    final baseUri = Uri.https(
      legalBaseHost,
      type == LegalDocumentType.termsOfUse
          ? '/apps/iplex/terms'
          : '/apps/iplex/policy',
    );

    return _applyLocale(baseUri, languageCode);
  }

  /// Verifies if a given URI satisfies security requirements for loading inside WebView.
  ///
  /// Requirements:
  /// - Only HTTPS allowed in production and staging.
  /// - Only authorized official domains or localhost in dev.
  /// - No arbitrary user-provided URLs or unsupported schemes.
  bool isAllowedLegalUrl(Uri uri) {
    if (!uri.hasScheme) return false;

    // Strict scheme enforcement
    if (environment == LegalEnvironment.production ||
        environment == LegalEnvironment.staging) {
      if (uri.scheme.toLowerCase() != 'https') return false;
    } else {
      if (uri.scheme.toLowerCase() != 'https' &&
          uri.scheme.toLowerCase() != 'http') {
        return false;
      }
    }

    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;

    // Allowed official domains
    if (authorizedDomains.contains(host)) return true;

    // Subdomains of iplex.app or web.app for project
    if (host.endsWith('.iplex.app') ||
        host == 'iplex-2c8fc.web.app' ||
        host == 'iplex-2c8fc.firebaseapp.com') {
      return true;
    }

    // Dev hosts in development mode
    if (environment == LegalEnvironment.development) {
      if (host == 'localhost' ||
          host == devLocalHost ||
          host == devAndroidHost) {
        return true;
      }
    }

    // Custom build-time hosts if explicitly injected
    final customTermsHost = Uri.tryParse(customTermsUrl)?.host.toLowerCase();
    if (customTermsHost != null &&
        customTermsHost.isNotEmpty &&
        host == customTermsHost) {
      return uri.scheme.toLowerCase() == 'https';
    }
    final customPrivacyHost = Uri.tryParse(customPrivacyUrl)?.host
        .toLowerCase();
    if (customPrivacyHost != null &&
        customPrivacyHost.isNotEmpty &&
        host == customPrivacyHost) {
      return uri.scheme.toLowerCase() == 'https';
    }

    return false;
  }

  /// Checks whether an external navigation target is a legitimate HTTPS external link
  /// that should be opened in the external system browser rather than inside the WebView.
  bool isLegitimateExternalLink(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    return !isAllowedLegalUrl(uri);
  }

  Uri _applyLocale(Uri uri, String? languageCode) {
    if (languageCode == null || languageCode.isEmpty) return uri;
    final normalized = languageCode.split('_').first.toLowerCase();
    if (normalized != 'en' && normalized != 'pt' && normalized != 'es') {
      return uri;
    }
    final params = Map<String, String>.from(uri.queryParameters);
    params['lang'] = normalized;
    return uri.replace(queryParameters: params);
  }
}
