// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get home => 'Home';

  @override
  String get users => 'Users';

  @override
  String get devices => 'Devices';

  @override
  String get iptv => 'IPTV';

  @override
  String get account => 'Account';

  @override
  String get welcome => 'Your entertainment.\nIn your hands.';

  @override
  String get loginSubtitle =>
      'Manage your family, connect your TVs and make yourself at home.';

  @override
  String get google => 'Continue with Google';

  @override
  String get apple => 'Continue with Apple';

  @override
  String get terms => 'Terms of use';

  @override
  String get privacy => 'Privacy policy';

  @override
  String get configurationRequired =>
      'Connection not configured. Contact support to enable this installation.';

  @override
  String get search => 'Search your catalog';

  @override
  String get catalog => 'Your catalog';

  @override
  String get catalogSubtitle => 'Discover here. Watch on your TV.';

  @override
  String get emptyCatalog => 'Your next discovery starts here';

  @override
  String get emptyCatalogBody =>
      'Add an IPTV source to bring your catalog together.';

  @override
  String get emptyUsers => 'A place for everyone';

  @override
  String get emptyDevices => 'Your TVs, connected';

  @override
  String get emptyDevicesBody =>
      'Scan the code displayed in iPlex Player to link your first TV.';

  @override
  String get emptySources => 'All your sources, together';

  @override
  String get emptySourcesBody =>
      'Connect an M3U or Xtream Codes source. Your catalog stays synchronized in the cloud.';

  @override
  String get empty => 'Nothing here yet';

  @override
  String get error => 'We could not complete this request.';

  @override
  String get retry => 'Try again';

  @override
  String get add => 'Add';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get remove => 'Remove';

  @override
  String get confirmRemoval => 'Remove this item?';

  @override
  String get removalBody => 'This action removes access and cannot be undone.';

  @override
  String get name => 'Name';

  @override
  String get requiredField => 'Enter a valid value.';

  @override
  String get family => 'Family accounts';

  @override
  String get profiles => 'Viewing profiles';

  @override
  String get createFamily => 'Create a family';

  @override
  String get joinFamily => 'Join a family';

  @override
  String get familyIntro =>
      'Use your personal account or create a family whenever you want.';

  @override
  String get invite => 'Invite a member';

  @override
  String get newProfile => 'New viewing profile';

  @override
  String get administrator => 'Administrator';

  @override
  String get member => 'Member';

  @override
  String get inviteExpires => 'Single-use invitation. Valid for 5 minutes.';

  @override
  String get expired => 'Expired';

  @override
  String get scan => 'Scan QR code';

  @override
  String get scanHelp => 'Position the iPlex QR code inside the camera view.';

  @override
  String get invalidCode => 'This code is invalid, expired or already used.';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get lastSeen => 'Last connection';

  @override
  String get up => 'Up';

  @override
  String get down => 'Down';

  @override
  String get left => 'Left';

  @override
  String get right => 'Right';

  @override
  String get ok => 'OK';

  @override
  String get back => 'Back';

  @override
  String get sent => 'Sent to Player';

  @override
  String get acknowledged => 'Received by Player';

  @override
  String get noAcknowledgement => 'Player did not confirm receipt.';

  @override
  String get source => 'Source';

  @override
  String get sourceUrl => 'Source URL (HTTP or HTTPS)';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get credentialsHint =>
      'Credentials are encrypted on the server and are never displayed after saving.';

  @override
  String get sourceReady => 'Synchronized';

  @override
  String get sourceQueued => 'Waiting to synchronize';

  @override
  String get sourceSyncing => 'Synchronizing';

  @override
  String get sourceError => 'Sync failed. Previous catalog preserved.';

  @override
  String get sourceFailure => 'Failure';

  @override
  String get subscription => 'Player subscription';

  @override
  String get trialNotStarted =>
      'Your 7-day trial starts when you link your first TV.';

  @override
  String get trialActive => 'Free trial active';

  @override
  String get subscriptionActive => 'Subscription active';

  @override
  String get subscriptionCancelled => 'Subscription cancelled';

  @override
  String get subscriptionExpired => 'Subscription expired';

  @override
  String get subscriptionPending => 'Subscription pending';

  @override
  String get monthly => 'Monthly';

  @override
  String get annual => 'Annual';

  @override
  String get billingUnavailable =>
      'Purchases are not available yet. No payment will be charged.';

  @override
  String get settings => 'Settings';

  @override
  String get preferences => 'Preferences';

  @override
  String get language => 'Language';

  @override
  String get systemLanguage => 'Device language';

  @override
  String get myProfile => 'My profile';

  @override
  String get help => 'Help & support';

  @override
  String get about => 'About';

  @override
  String get aboutBody =>
      'iPlex manages your ecosystem. Playback takes place exclusively in iPlex Player on your TV.';

  @override
  String get logout => 'Sign out';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountBody =>
      'You will be asked to sign in again. Remove family members before deleting an administrator account. Your data will be queued for permanent deletion.';

  @override
  String get favorites => 'Favorites';

  @override
  String get favorite => 'Add to favorites';

  @override
  String get unavailable => 'Unavailable';

  @override
  String get more => 'Load more';

  @override
  String get noResults => 'No matching content';

  @override
  String get notFound => 'Page not found';

  @override
  String get accessDenied => 'You do not have permission for this action.';

  @override
  String get familyLimit => 'This family already has five accounts.';

  @override
  String get requiresLogin => 'Please sign in again to continue.';

  @override
  String get appVerificationFailed =>
      'We could not verify this app with the server. Your session is still active; try again in a few minutes.';

  @override
  String get familyHasMembers =>
      'Remove the family members before deleting your account.';

  @override
  String get loading => 'Loading';

  @override
  String get edit => 'Edit';

  @override
  String get continueWatching => 'Continue watching on TV';

  @override
  String sessionLimit(String devices) {
    return 'Three TVs are already in use: $devices.';
  }

  @override
  String profileInUse(String device) {
    return 'This profile is in use on $device.';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'No items',
    );
    return '$_temp0';
  }

  @override
  String get homeWelcome => 'Welcome to iPlex';

  @override
  String get homeSetupBody =>
      'Set up your devices and content sources to get started.';

  @override
  String get catalogEmptyBody =>
      'This source has no content available yet. You can review your sources or link a TV.';

  @override
  String get addDevice => 'Add device';

  @override
  String get configureIptv => 'Configure IPTV';

  @override
  String get manageFamily => 'Manage family accounts';

  @override
  String get familyRequiredBody =>
      'Create or join a family in Users to manage devices and profiles. Home and IPTV remain available.';

  @override
  String get familyUnavailable => 'Family information is unavailable';

  @override
  String get memberSetupHint =>
      'Your family administrator can add devices, profiles and content sources. You can browse the available information here.';

  @override
  String get restoringSession => 'Checking your session…';

  @override
  String get loadingAccount => 'Preparing your account…';

  @override
  String get sessionLoadError =>
      'We could not prepare your session. Check your connection and try again.';

  @override
  String get catalogPreparing =>
      'Your sources are waiting to synchronize. Content will appear here when processing is complete.';

  @override
  String get catalogSyncFailed => 'We could not synchronize your catalog';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get noResultsBody =>
      'Try another title or clear the search to see the available catalog.';

  @override
  String get noProfilesBody =>
      'Create a viewing profile before adding favorites.';

  @override
  String get unlinkedAccount => 'No family linked';

  @override
  String get iptvSubtitle => 'Manage your content sources';

  @override
  String get emptySourcesTitle => 'No IPTV sources';

  @override
  String get emptySourcesDescription =>
      'Add your first source to make content available in iPlex.';

  @override
  String get addSource => 'Add source';

  @override
  String get editSource => 'Edit source';

  @override
  String get syncNow => 'Sync now';

  @override
  String get deleteSource => 'Delete source';

  @override
  String get confirmDeleteSourceTitle => 'Delete IPTV source?';

  @override
  String get confirmDeleteSourceBody =>
      'This action will remove the source and linked contents from your catalog. Do you wish to continue?';

  @override
  String lastSync(String time) {
    return 'Last sync: $time';
  }

  @override
  String get neverSynced => 'Never synchronized';

  @override
  String get sourceType => 'Source type';

  @override
  String get sourceFormatM3u => 'M3U / M3U8';

  @override
  String get sourceFormatXtream => 'Xtream Codes';

  @override
  String get sourceValidating => 'Validating connection';

  @override
  String get sourceHost => 'Server';

  @override
  String get syncInProgress => 'Sync in progress…';

  @override
  String get syncRequested => 'Synchronization requested successfully.';

  @override
  String get catalogSummary => 'Catalog contents';

  @override
  String get passwordKeepHint => 'Leave blank to keep current password';

  @override
  String get playlistUrl => 'Playlist URL';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get sourceDetails => 'Source details';

  @override
  String get syncErrorGeneric =>
      'Failed to synchronize with provider. Previous catalog preserved.';

  @override
  String get noConnection => 'No connection to server';

  @override
  String get adminOnlyAction =>
      'Only the family administrator can manage IPTV sources.';

  @override
  String get managerAccessTitle => 'Free iPlex Gestor';

  @override
  String get managerAccessBody =>
      'Manage your family, profiles, devices and IPTV sources for free, even after your trial ends. Playback in iPlex Player requires a valid trial or subscription.';

  @override
  String get subscriptionManagedByAdmin =>
      'Your family subscription details are available to its administrator. You can consult the Player plans below.';

  @override
  String get playbackSubscriptionRequired =>
      'Playback requires a valid trial or subscription. Check the Player plans in Account.';

  @override
  String get sourceFormatUrl => 'URL';

  @override
  String get sourceFormatFile => 'File';

  @override
  String get sourceFormatOtherM3u8 => 'Alternative M3U8';

  @override
  String get sourceFile => 'M3U / M3U8 File';

  @override
  String get selectFile => 'Select file';

  @override
  String get changeFile => 'Replace file';

  @override
  String get noFileSelected => 'No file selected';

  @override
  String fileSelected(String fileName, String size) {
    return 'File: $fileName ($size)';
  }

  @override
  String get invalidFileFormat =>
      'Invalid file format. Select a valid .m3u or .m3u8 file.';

  @override
  String get fileTooLarge => 'File exceeds the 20MB limit.';

  @override
  String get epgUrl => 'EPG URL (optional)';

  @override
  String get protectPlaylist => 'Protect playlist';

  @override
  String get protectPlaylistHint => 'Require PIN to access this source';

  @override
  String get pin => 'PIN';

  @override
  String get confirmPin => 'Confirm PIN';

  @override
  String get pinMustMatch => 'PINs do not match.';

  @override
  String get pinLengthError => 'PIN must be between 4 and 6 digits.';

  @override
  String get pinRequired => 'PIN is required when protection is enabled.';

  @override
  String get enterPinTitle => 'Protected source';

  @override
  String get enterPinBody => 'Enter security PIN to access this source.';

  @override
  String get unlock => 'Unlock';

  @override
  String incorrectPin(int remaining) {
    return 'Incorrect PIN. $remaining attempts remaining.';
  }

  @override
  String get pinLocked => 'Too many failed attempts. Try again later.';

  @override
  String get singleStream => 'Individual stream';

  @override
  String get keepExistingPin => 'Keep existing PIN';

  @override
  String get changePin => 'Change PIN';

  @override
  String get fileKeepHint => 'Leave unselected to keep current file';

  @override
  String get otherM3u8Url => 'Alternative M3U8 URL';

  @override
  String get protectedBadge => 'Protected';

  @override
  String fileLabel(String fileName) {
    return 'File: $fileName';
  }

  @override
  String get confirmChangeFormatTitle => 'Change source format?';

  @override
  String get confirmChangeFormatBody =>
      'Changing the source format will require reconfiguring the source settings. Do you want to continue?';

  @override
  String get invalidInput => 'Review the fields and try saving again.';

  @override
  String get connectionFailure =>
      'Could not connect to the service. Check your connection and try again.';

  @override
  String get requestTimeout =>
      'The request took longer than expected. Check whether the change was saved before trying again.';

  @override
  String get accountUnavailable =>
      'Could not access your settings. Refresh the screen or sign in again.';

  @override
  String get sourceCredentialsRequired =>
      'Enter the source username and password.';

  @override
  String get sourceUrlInvalid =>
      'Enter a valid URL (HTTP or HTTPS) without spaces or credentials before the server address.';

  @override
  String get iptvKeepConnection =>
      'Leave connection fields blank to keep the saved credentials and URLs. Enter a complete value to replace one.';

  @override
  String get iptvRemoveEpg => 'Remove saved EPG';

  @override
  String get iptvEpgConfigured => 'EPG configured';

  @override
  String get iptvSourceConflict =>
      'This source changed. Reopen the form before saving.';

  @override
  String get iptvRateLimited => 'Please wait a moment before trying again.';

  @override
  String get iptvSourceLimit => 'The limit of 100 sources has been reached.';

  @override
  String get legal => 'Legal';

  @override
  String get legalLoading => 'Loading document…';

  @override
  String get legalErrorGeneric => 'Unable to load document.';

  @override
  String get legalErrorNetwork =>
      'Check your internet connection and try again.';

  @override
  String get legalErrorBlocked => 'Navigation to this address is not allowed.';

  @override
  String get syncSuccessTitle => 'IPTV synced';

  @override
  String get syncSuccessBody =>
      'Your IPTV playlist has been successfully updated.';

  @override
  String get viewIptv => 'View IPTV';

  @override
  String get close => 'Close';

  @override
  String get syncFailureTitle => 'Sync failed';

  @override
  String get errorCannotConnect => 'Could not connect to the server.';

  @override
  String get errorInvalidCredentials => 'Invalid credentials.';

  @override
  String get errorInvalidPlaylist => 'Invalid playlist.';

  @override
  String get errorConnectionTimeout => 'Connection timed out.';

  @override
  String get errorTemporaryProcessing => 'Temporary processing error.';

  @override
  String get errorInvalidSourceUrl => 'The IPTV address is invalid.';

  @override
  String get errorUnrecognizedSourceFormat =>
      'Could not identify the IPTV format.';

  @override
  String get errorProviderRateLimited =>
      'The server is rate limiting requests. Please try again later.';

  @override
  String get errorProviderTimeBudget => 'The server took too long to respond.';

  @override
  String get errorDownloadFailed => 'Could not download IPTV data.';

  @override
  String get errorCatalogTooLarge =>
      'The playlist exceeds the allowed processing limit.';

  @override
  String get errorSuspiciousCatalog =>
      'The received playlist is empty or incomplete.';

  @override
  String get errorDuplicateContent =>
      'The playlist contains duplicate content.';

  @override
  String get errorHlsOriginRequired =>
      'The HLS stream requires a valid origin address.';

  @override
  String get errorParsingFailed => 'Could not parse the IPTV data.';

  @override
  String get errorNormalizationFailed => 'Could not prepare the catalog.';

  @override
  String get errorStorageUploadFailed =>
      'Could not store the processed catalog.';

  @override
  String get errorCatalogPublicationFailed =>
      'Could not finalize the catalog update.';

  @override
  String get errorCatalogSyncFailed =>
      'Could not complete the synchronization.';

  @override
  String get errorUnsafeProvider => 'Address not allowed for security reasons.';

  @override
  String get pushSuccessTitle => 'IPTV synced';

  @override
  String pushSuccessBody(String name) {
    return 'Playlist \"$name\" is ready to use.';
  }

  @override
  String get pushFailureTitle => 'Failed to sync IPTV';

  @override
  String pushFailureBody(String name) {
    return 'Could not update \"$name\". Tap to check.';
  }

  @override
  String get deviceFound => 'Device found';

  @override
  String get deviceFoundBody =>
      'A TV was detected. Confirm the details below to link it.';

  @override
  String get deviceLinked => 'Device linked';

  @override
  String deviceLinkedBody(String name) {
    return 'The TV \"$name\" is now linked.';
  }

  @override
  String get deviceAlreadyLinked => 'Device already linked';

  @override
  String get deviceAlreadyLinkedOtherFamily =>
      'This TV is already linked to another family. Unlink it from its previous family before connecting here.';

  @override
  String get deviceAlreadyLinkedSameFamily => 'This TV is already linked here.';

  @override
  String get deviceOffline => 'Device offline';

  @override
  String get invalidQrCode =>
      'Invalid QR Code. Please check the code displayed on your TV.';

  @override
  String get expiredQrCode =>
      'This QR Code has expired. Please generate a new one on your TV.';

  @override
  String get invalidPairingCode =>
      'Incorrect pairing code. Check the code on the TV and try again.';

  @override
  String get cameraPermissionDenied => 'Camera access denied';

  @override
  String get cameraPermissionHelp =>
      'Camera access is needed to scan the QR Code on your TV. You can also enter the code manually.';

  @override
  String get cameraUnavailable =>
      'Camera unavailable on this device. Please enter the pairing code manually.';

  @override
  String get pairingCancelled => 'Pairing cancelled';

  @override
  String get pairingCompleted => 'Pairing completed';

  @override
  String get connectionFailed =>
      'Connection failed. Please check your internet connection.';

  @override
  String get deviceUnlinked => 'Device unlinked';

  @override
  String get deviceUnlinkedBody =>
      'The device has been successfully removed from this family.';

  @override
  String get noDevicePermission =>
      'Only family administrators can manage devices.';

  @override
  String get addDeviceInstructionsTitle => 'How to connect your TV';

  @override
  String get addDeviceStep1 => '1. Open the iPlex Player app on your TV.';

  @override
  String get addDeviceStep2 =>
      '2. Wait for the QR code and pairing code to appear.';

  @override
  String get addDeviceStep3 =>
      '3. Scan the QR code with your camera or enter the code manually.';

  @override
  String get addDeviceStep4 => '4. Confirm the device details to finish.';

  @override
  String get scanQrCode => 'Scan QR Code';

  @override
  String get enterCodeManually => 'Enter code manually';

  @override
  String get enterCodeTitle => 'Enter pairing code';

  @override
  String get enterCodeHint => 'e.g. 749-281';

  @override
  String get enterCodeHelp => 'Enter the 6-digit code shown on your TV screen.';

  @override
  String get confirmPairingTitle => 'Confirm device link';

  @override
  String get confirmPairingSubtitle =>
      'Review the TV information before linking.';

  @override
  String get tvNameLabel => 'TV Name';

  @override
  String get platformLabel => 'Platform';

  @override
  String get manufacturerLabel => 'Manufacturer';

  @override
  String get modelLabel => 'Model';

  @override
  String get targetFamilyLabel => 'Destination family';

  @override
  String get maskedIdLabel => 'Device ID';

  @override
  String get identityStabilityLabel => 'Identity type';

  @override
  String get confirmLinkButton => 'Link device';

  @override
  String get cancelLinkButton => 'Cancel';

  @override
  String get viewDetails => 'View details';

  @override
  String get backToDevices => 'Back to devices';

  @override
  String get unlinkDevice => 'Unlink device';

  @override
  String get unlinkConfirmTitle => 'Unlink this TV?';

  @override
  String get unlinkConfirmBody =>
      'This TV will lose access to all family contents and will need to be paired again to reconnect.';

  @override
  String get editDeviceName => 'Edit TV Name';

  @override
  String get deviceDetailsTitle => 'Device Details';

  @override
  String get technicalDetails => 'Technical info';

  @override
  String get linkedAtLabel => 'Linked on';

  @override
  String get lastActivityLabel => 'Last activity';

  @override
  String get neverActive => 'No activity recorded yet';

  @override
  String get publicUserCode => 'User code';

  @override
  String get publicIdentityHelp =>
      'Public identification for membership requests. This is not a password or a TV code.';

  @override
  String get identityUnavailable =>
      'Identification unavailable. Please sign in again.';

  @override
  String get copyPublicCode => 'Copy code';

  @override
  String get codeCopied => 'Code copied';

  @override
  String get publicIdentityScanHelp =>
      'Scan the user QR code displayed on the iPlex Home screen.';

  @override
  String get invalidPublicCode =>
      'Enter a 12-character alphanumeric user code.';

  @override
  String get personalContext => 'Personal account';

  @override
  String get selectedContext => 'Selected context';

  @override
  String get membershipRequests => 'Membership requests';

  @override
  String get membershipAcceptHelp =>
      'Accepting moves your account into this family. If your individual family has IPTV sources, devices or profiles, remove them first.';

  @override
  String get acceptMembership => 'Accept';

  @override
  String get declineMembership => 'Decline';

  @override
  String get sendMembershipRequest => 'Request membership';

  @override
  String get membershipSent => 'Request sent. Awaiting acceptance.';

  @override
  String get shareApplication => 'Share application';

  @override
  String get provisionalShareMessage =>
      'Discover iPlex. The official installation link will be available soon.';

  @override
  String get publicUserUnavailable =>
      'User not found or unavailable for membership.';

  @override
  String get membershipExpired =>
      'This request has expired or is no longer available.';

  @override
  String get shareUnavailable => 'Sharing is unavailable on this device.';

  @override
  String get familyTitle => 'Family';

  @override
  String get pairingExpired =>
      'This TV code has expired or was already used. Wait for the TV to show a new one.';

  @override
  String get deviceLinkedElsewhere =>
      'This TV is already linked to another account. Unlink it there first.';

  @override
  String get errorInvalidEpg => 'The program guide (EPG) could not be read.';

  @override
  String get errorCatalogIntegrity =>
      'The generated catalog failed the integrity check. The previous catalog was kept.';

  @override
  String get errorWorkerRetriesExhausted =>
      'Synchronization failed after several attempts. Please try again later.';

  @override
  String get errorSourceSecretUnavailable =>
      'Saved credentials could not be read. Edit the source and enter them again.';

  @override
  String get profileType => 'Profile type';

  @override
  String get profileTypeRegular => 'Standard';

  @override
  String get profileTypeKids => 'Kids';

  @override
  String get profileTypeAdmin => 'Administrator';

  @override
  String get profileTypeGuest => 'Guest';

  @override
  String get manageProfile => 'Manage profile';

  @override
  String get profileInfo => 'Profile information';

  @override
  String get accountLinked => 'Linked to an account';

  @override
  String get accountNotLinked => 'No linked account';

  @override
  String get linkAccount => 'Link to an account';

  @override
  String get unlinkAccount => 'Unlink account';

  @override
  String get unlinkAccountTitle => 'Unlink account?';

  @override
  String unlinkAccountBody(String name) {
    return 'The account will stop using $name. The profile and its favorites, history, progress and permissions are kept.';
  }

  @override
  String get linkCodeTitle => 'Link code';

  @override
  String get linkCodeBody =>
      'On the person\'s account, open Family › Link to a profile and scan this QR code or type the code. Single use, valid for 10 minutes.';

  @override
  String get permissionsTitle => 'Permissions';

  @override
  String get allSpaces => 'All spaces';

  @override
  String get allSpacesHint => 'Includes sources added later.';

  @override
  String get spaceLive => 'Live channels';

  @override
  String get spaceMovies => 'Movies';

  @override
  String get spaceSeries => 'Series';

  @override
  String get kidsRestrictionNote =>
      'Kids profiles only receive content identified as for children. This system restriction cannot be turned off.';

  @override
  String get adminFullAccess => 'The administrator can access every space.';

  @override
  String get noFamilySources => 'This family has no IPTV sources.';

  @override
  String get manageData => 'Data management';

  @override
  String get clearFavorites => 'Clear favorites';

  @override
  String get clearFavoritesTitle => 'Clear favorites?';

  @override
  String clearFavoritesBody(String name) {
    return 'All of $name\'s favorites will be permanently deleted. This can\'t be undone. The deletion will sync to every device.';
  }

  @override
  String get clearWatched => 'Clear watched';

  @override
  String get clearWatchedTitle => 'Clear watched history?';

  @override
  String clearWatchedBody(String name) {
    return 'All of $name\'s watched history will be permanently deleted. This can\'t be undone. The deletion will sync to every device.';
  }

  @override
  String get clearContinueWatching => 'Clear Continue watching';

  @override
  String get clearProgressTitle => 'Clear Continue watching?';

  @override
  String clearProgressBody(String name) {
    return 'All of $name\'s saved playback progress will be permanently deleted. This can\'t be undone. The deletion will sync to every device.';
  }

  @override
  String get clearProgress => 'Clear progress';

  @override
  String get dataCleared => 'Data deleted.';

  @override
  String get addGuest => 'Add guest';

  @override
  String get guestEnabled => 'Guest available on the TV';

  @override
  String get guestHint =>
      'The guest doesn\'t save favorites, history or progress.';

  @override
  String get linkToProfile => 'Link to a profile';

  @override
  String get linkToProfileBody =>
      'Type the code or scan the QR code shown by the family administrator.';

  @override
  String get linkCode => 'Code';

  @override
  String get profileLinked => 'Your account is now linked to the profile.';

  @override
  String get errorProfileLimit => 'This family already has four members.';

  @override
  String get errorProfileTypeImmutable => 'The profile type can\'t be changed.';

  @override
  String get errorAccountAlreadyLinked =>
      'This account is already linked to a profile in this family.';

  @override
  String get errorProfileAlreadyLinked =>
      'This profile is already linked to an account.';

  @override
  String get errorLinkCodeExpired =>
      'This code has expired or was already used. Ask the administrator for a new one.';

  @override
  String get errorClearInProgress =>
      'A clear is already running for this profile.';

  @override
  String get errorClearFailed =>
      'The deletion could not be completed. Try again; nothing will be duplicated.';

  @override
  String get errorGuestNotPersisted => 'The guest doesn\'t save data.';

  @override
  String get errorAdministratorProtected =>
      'The administrator profile can\'t be changed this way.';

  @override
  String get disabled => 'Disabled';

  @override
  String get subscriptionsComingSoon => 'Subscriptions available soon.';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get restorePurchases => 'Restore purchases';

  @override
  String get manageSubscriptionPlay => 'Manage subscription on Google Play';

  @override
  String get purchasePending =>
      'Payment pending. Access starts once Google Play confirms it.';

  @override
  String get purchaseVerifying => 'Confirming the purchase with Google Play…';

  @override
  String get purchaseConfirmed => 'Subscription confirmed.';

  @override
  String get purchaseCanceled => 'Purchase cancelled. Nothing was charged.';

  @override
  String get storeUnavailable => 'The store isn\'t available on this device.';

  @override
  String get playbackSubscriptionNote =>
      'The subscription unlocks playback in iPlex Player for the family. The Manager stays free.';

  @override
  String get errorPaymentsDisabled => 'Subscriptions aren\'t available yet.';

  @override
  String get errorPurchaseInvalid =>
      'The purchase couldn\'t be validated with Google Play.';

  @override
  String get errorPurchaseAccount =>
      'This purchase belongs to another account.';

  @override
  String get errorPurchaseUsed =>
      'This purchase is already linked to another family.';

  @override
  String get watchOnTv => 'Watch on TV';

  @override
  String get chooseTv => 'Choose the TV';

  @override
  String get noTvLinked => 'No linked TV';

  @override
  String get noTvLinkedBody =>
      'Link a TV in Devices to start titles on it from here.';

  @override
  String get tvNotReady =>
      'Open iPlex on the TV and choose a profile to receive the request.';

  @override
  String get chooseEpisode => 'Choose the episode';

  @override
  String seasonNumber(int number) {
    return 'Season $number';
  }

  @override
  String episodeNumber(String number) {
    return 'E$number';
  }

  @override
  String get noEpisodes => 'No episodes are available for this series yet.';

  @override
  String sendingToTv(String tv) {
    return 'Sending to $tv…';
  }

  @override
  String tvReceivedRequest(String tv) {
    return '$tv received the request.';
  }

  @override
  String waitingTvConfirmation(String tv) {
    return 'Waiting for confirmation on $tv: something is already playing there.';
  }

  @override
  String playingOnTv(String tv) {
    return 'Playing on $tv.';
  }

  @override
  String openedOnTv(String tv) {
    return 'Opened on $tv. Choose the episode with the TV remote.';
  }

  @override
  String get tvKeptCurrent => 'The TV kept the current playback.';

  @override
  String get tvNoAnswer =>
      'Nobody confirmed on the TV. The current playback continues.';

  @override
  String get tvDidNotRespond =>
      'The TV did not respond. Check that iPlex is open on it and try again.';

  @override
  String get playRequestExpired =>
      'The request expired before reaching the TV. Try again.';

  @override
  String get playRequestSuperseded => 'A newer request replaced this one.';

  @override
  String get playRequestFailed => 'The TV could not play this title.';

  @override
  String get contentNotAllowedOnTv =>
      'This title is not available for the profile in use on the TV.';

  @override
  String get sourceProtectedOnTv =>
      'This source is PIN-protected and cannot be played on the TV yet.';

  @override
  String get streamUnavailableOnTv =>
      'The IPTV source did not release this title now. Try again later.';

  @override
  String get formatUnsupportedOnTv =>
      'The TV cannot play the format of this title.';

  @override
  String get episodeRequired => 'Choose an episode to watch on the TV.';

  @override
  String get deviceNotFound => 'This TV is no longer linked.';

  @override
  String get tvDone => 'Done';

  @override
  String get parentalControl => 'Parental control';

  @override
  String get parentalControlBody =>
      'When the family has a kids profile, adult profiles only open on the TV with the parental PIN. The PIN is checked by the iPlex server.';

  @override
  String get parentalPinConfigured => 'Parental PIN set';

  @override
  String get parentalPinMissing => 'Parental PIN not set';

  @override
  String get parentalPinMissingKids =>
      'There is a kids profile: adult profiles stay locked on the TV until you set the PIN.';

  @override
  String get setParentalPin => 'Set PIN';

  @override
  String get changeParentalPin => 'Change PIN';

  @override
  String get removeParentalPin => 'Remove PIN';

  @override
  String get removeParentalPinBody =>
      'While there is a kids profile, adult profiles will stay locked on the TV.';

  @override
  String get parentalPinLength => 'Use 4 digits.';

  @override
  String get parentalPinSaved => 'Parental PIN saved.';

  @override
  String get parentalPinRemoved => 'Parental PIN removed.';

  @override
  String get sourceRetrying => 'Retrying automatically';

  @override
  String get previousCatalogKept => 'The previous catalog was kept.';

  @override
  String technicalDetail(String detail) {
    return 'Technical detail: $detail';
  }

  @override
  String catalogKinds(int channels, int movies, int series) {
    return '$channels channels · $movies movies · $series series';
  }

  @override
  String get homeRecentSearches => 'Recently searched';

  @override
  String get homeSearchHint => 'Search';

  @override
  String get selectIptvSource => 'Select IPTV source';

  @override
  String get iptvSources => 'IPTV sources';

  @override
  String get selectedSource => 'Selected';

  @override
  String get homeFavorites => 'Favorites';

  @override
  String get homeContinueWatching => 'Continue watching';

  @override
  String get homeMyList => 'My list';

  @override
  String get homeRecentMovies => 'Recently added movies';

  @override
  String get homeRecentSeries => 'Recently added series';

  @override
  String get homeEmptyTitle => 'Your Home is still empty';

  @override
  String get homeEmptyBody =>
      'Search channels, movies and series. What you favorite, save to your list or start watching shows up here.';

  @override
  String get exploreCatalog => 'Explore the catalog';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get addToMyList => 'Add to My list';

  @override
  String get removeFromMyList => 'Remove from My list';

  @override
  String get continueWatchingOnTv => 'Continue watching on TV';

  @override
  String get liveChannel => 'Live channel';

  @override
  String get onAirNow => 'Now';

  @override
  String get upNext => 'Up next';

  @override
  String get castLabel => 'Cast';

  @override
  String runtimeMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String seasonsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seasons',
      one: '1 season',
    );
    return '$_temp0';
  }

  @override
  String episodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
    );
    return '$_temp0';
  }

  @override
  String get episodesTitle => 'Episodes';

  @override
  String get showMore => 'Show more';

  @override
  String get showLess => 'Show less';

  @override
  String seasonEpisodeShort(int season, String episode) {
    return 'S${season}E$episode';
  }

  @override
  String ageRatingLabel(String rating) {
    return 'Rated $rating';
  }

  @override
  String familyOfName(String name) {
    return '$name family';
  }

  @override
  String get familyEmptyBody => 'No additional members yet.';

  @override
  String get addMembers => 'Add members';

  @override
  String get invitePending => 'Invitation pending';

  @override
  String get cancelInvitation => 'Cancel invitation';

  @override
  String get cancelInvitationBody =>
      'The invitation will no longer be valid and the person will not be able to accept it.';

  @override
  String get leaveFamily => 'Leave family';

  @override
  String get leaveFamilyBody =>
      'You return to your individual family. Your data is kept.';

  @override
  String get errorAlreadyInFamily =>
      'This account already belongs to a family.';

  @override
  String get errorIndividualFamilyHasResources =>
      'To join another family, first remove the IPTV sources, devices and profiles of your individual family.';

  @override
  String get errorFamilyExclusive => 'Each account belongs to a single family.';

  @override
  String get homeWishlist => 'Wishlist';

  @override
  String get addToWishlist => 'Add to wishlist';

  @override
  String get removeFromWishlist => 'Remove from wishlist';

  @override
  String get notAvailableToWatch =>
      'Not available to watch in your IPTV catalog. You can still save it.';

  @override
  String originalTitleLabel(String title) {
    return 'Original title: $title';
  }

  @override
  String releaseDateLabel(String date) {
    return 'Released $date';
  }

  @override
  String ratingLabel(String score) {
    return 'Rating $score/10 (TMDB)';
  }

  @override
  String get crewLabel => 'Crew';

  @override
  String get seasonsTitle => 'Seasons';

  @override
  String get seasonsFromTmdb =>
      'Editorial information from TMDB. Availability depends on your IPTV source.';

  @override
  String get availableEpisodesTitle => 'Available on your IPTV';

  @override
  String get filmography => 'Filmography';

  @override
  String get careerTimeline => 'Career timeline';

  @override
  String get biography => 'Biography';

  @override
  String bornLabel(String date) {
    return 'Born $date';
  }

  @override
  String diedLabel(String date) {
    return 'Died $date';
  }

  @override
  String get moviesLabel => 'Movies';

  @override
  String get seriesLabel => 'Series';

  @override
  String get movieKind => 'Movie';

  @override
  String get seriesKind => 'Series';

  @override
  String asCharacter(String character) {
    return 'as $character';
  }

  @override
  String get undatedLabel => 'No date';

  @override
  String get metadataUnavailable =>
      'Information about this title is unavailable right now.';

  @override
  String get personUnavailable =>
      'Information about this person is unavailable right now.';

  @override
  String get discoveryNotAllowed =>
      'This profile only shows titles from your catalog.';

  @override
  String get errorContentUnavailable =>
      'This title is not available for this profile.';

  @override
  String get errorStaleLibrary =>
      'Your lists were updated on another device. Try again.';

  @override
  String directedByLabel(String names) {
    return 'Directed by $names';
  }

  @override
  String createdByLabel(String names) {
    return 'Created by $names';
  }

  @override
  String get andConjunction => 'and';

  @override
  String get continueLabel => 'Continue';

  @override
  String get restartLabel => 'Start over';

  @override
  String get favoriteAction => 'Favorite';

  @override
  String get unfavoriteAction => 'Unfavorite';

  @override
  String get saveAction => 'Save';

  @override
  String get unsaveAction => 'Remove';

  @override
  String seasonEpisodeLabel(int season, int episode) {
    return 'Season $season - Episode $episode';
  }

  @override
  String get socialNetworks => 'Social media';
}
