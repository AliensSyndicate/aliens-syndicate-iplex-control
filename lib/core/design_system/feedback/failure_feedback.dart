import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../components/app_modal_sheet.dart';
import '../components/neumorphic_action_button.dart';
import '../localized_context.dart';

String failureText(BuildContext context, Object error) {
  final l = context.l;
  if (error is! AppFailure) return l.error;
  return switch (error.code) {
    'configuration-required' => l.configurationRequired,
    'user-unavailable' => l.publicUserUnavailable,
    'invitation-expired' => l.membershipExpired,
    'share-unavailable' => l.shareUnavailable,
    'identity-conflict' || 'identity-unavailable' => l.identityUnavailable,
    'invalid-token' => l.invalidCode,
    'pairing-expired' => l.pairingExpired,
    'payments-disabled' => l.errorPaymentsDisabled,
    'purchase-invalid' => l.errorPurchaseInvalid,
    'purchase-account-mismatch' => l.errorPurchaseAccount,
    'purchase-already-used' => l.errorPurchaseUsed,
    'store-unavailable' => l.storeUnavailable,
    'profile-limit' => l.errorProfileLimit,
    'profile-type-immutable' => l.errorProfileTypeImmutable,
    'account-already-linked' => l.errorAccountAlreadyLinked,
    'profile-already-linked' || 'profile-not-linkable' => l.errorProfileAlreadyLinked,
    'link-code-expired' => l.errorLinkCodeExpired,
    'clear-in-progress' => l.errorClearInProgress,
    'clear-failed' => l.errorClearFailed,
    'guest-not-persisted' => l.errorGuestNotPersisted,
    'administrator-protected' => l.errorAdministratorProtected,
    'device-already-linked-elsewhere' => l.deviceLinkedElsewhere,
    'family-limit' => l.familyLimit,
    'session-limit' => l.sessionLimit(
      (error.details['devices'] as List?)?.join(', ') ?? '',
    ),
    'profile-in-use' => l.profileInUse(
      error.details['deviceName'] as String? ?? '',
    ),
    'permission-denied' => l.accessDenied,
    'unauthenticated' || 'requires-recent-login' => l.requiresLogin,
    'app-verification-failed' => l.appVerificationFailed,
    'family-has-members' => l.familyHasMembers,
    'device-offline' => l.remoteUnavailable,
    'subscription-required' => l.playbackSubscriptionRequired,
    'invalid-input' || 'invalid-argument' => l.invalidInput,
    'unavailable' || 'network-request-failed' => l.connectionFailure,
    'deadline-exceeded' => l.requestTimeout,
    'account-unavailable' || 'family-required' => l.accountUnavailable,
    'credentials-required' => l.sourceCredentialsRequired,
    'https-required' ||
    'epg-https-required' ||
    'url-required' => l.sourceUrlInvalid,
    'pin-required' => l.enterPinBody,
    'pin-mismatch' => l.pinMustMatch,
    'pin-locked' => l.pinLocked,
    'source-conflict' || 'request-conflict' => l.iptvSourceConflict,
    'rate-limited' => l.iptvRateLimited,
    'source-limit' => l.iptvSourceLimit,
    'file-required' || 'invalid-catalog' => l.invalidFileFormat,
    'file-too-large' || 'catalog-too-large' => l.fileTooLarge,
    _ => l.error,
  };
}

/// Project-wide modal sheet feedback for failure notices (replacing legacy SnackBars).
void showFailure(BuildContext context, Object error) {
  if (error is AppFailure &&
      [
        'cancelled',
        'popup-closed-by-user',
        'web-context-cancelled',
      ].contains(error.code)) {
    return;
  }
  showAppModalSheet<void>(
    context: context,
    useRootNavigator: true,
    title: context.l.error,
    description: failureText(context, error),
    actions: [
      AppButton(
        label: context.l.close,
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
    ],
  );
}

/// Project-wide modal sheet feedback for informative messages (replacing legacy SnackBars).
void showAppFeedbackSheet({
  required BuildContext context,
  required String message,
  String? title,
}) {
  showAppModalSheet<void>(
    context: context,
    useRootNavigator: true,
    title: title,
    description: message,
    actions: [
      AppButton(
        label: context.l.close,
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
    ],
  );
}

/// Mandatory project exception: device connection failure MUST be displayed via SnackBar.
void showDeviceConnectionFailure(BuildContext context, Object error) {
  if (error is AppFailure &&
      [
        'cancelled',
        'popup-closed-by-user',
        'web-context-cancelled',
      ].contains(error.code)) {
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(failureText(context, error)),
        behavior: SnackBarBehavior.floating,
      ),
    );
}
