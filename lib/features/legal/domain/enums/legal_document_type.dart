/// Typed identifier for legal documents supported in the iPlex ecosystem.
enum LegalDocumentType {
  termsOfUse,
  privacyPolicy;

  /// Parses a route parameter or identifier into a [LegalDocumentType].
  static LegalDocumentType? fromString(String? value) {
    if (value == null) return null;
    switch (value.trim().toLowerCase()) {
      case 'terms':
      case 'termsofuse':
      case 'terms-of-use':
      case 'terms_of_use':
        return LegalDocumentType.termsOfUse;
      case 'privacy':
      case 'privacypolicy':
      case 'privacy-policy':
      case 'privacy_policy':
        return LegalDocumentType.privacyPolicy;
      default:
        return null;
    }
  }

  /// Canonical semantic route path segment.
  String get pathSegment {
    switch (this) {
      case LegalDocumentType.termsOfUse:
        return 'terms';
      case LegalDocumentType.privacyPolicy:
        return 'privacy';
    }
  }
}
