import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('pt'),
  ];

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @users.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @iptv.
  ///
  /// In en, this message translates to:
  /// **'IPTV'**
  String get iptv;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Your entertainment.\nIn your hands.'**
  String get welcome;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your family, connect your TVs and make yourself at home.'**
  String get loginSubtitle;

  /// No description provided for @google.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get google;

  /// No description provided for @apple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get apple;

  /// No description provided for @terms.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get terms;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacy;

  /// No description provided for @configurationRequired.
  ///
  /// In en, this message translates to:
  /// **'Connection not configured. Contact support to enable this installation.'**
  String get configurationRequired;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search your catalog'**
  String get search;

  /// No description provided for @catalog.
  ///
  /// In en, this message translates to:
  /// **'Your catalog'**
  String get catalog;

  /// No description provided for @catalogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Discover here. Watch on your TV.'**
  String get catalogSubtitle;

  /// No description provided for @emptyDevices.
  ///
  /// In en, this message translates to:
  /// **'Your TVs, connected'**
  String get emptyDevices;

  /// No description provided for @emptyDevicesBody.
  ///
  /// In en, this message translates to:
  /// **'Scan the code displayed in iPlex Player to link your first TV.'**
  String get emptyDevicesBody;

  /// No description provided for @emptySources.
  ///
  /// In en, this message translates to:
  /// **'All your sources, together'**
  String get emptySources;

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get empty;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'We could not complete this request.'**
  String get error;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @confirmRemoval.
  ///
  /// In en, this message translates to:
  /// **'Remove this item?'**
  String get confirmRemoval;

  /// No description provided for @removalBody.
  ///
  /// In en, this message translates to:
  /// **'This action removes access and cannot be undone.'**
  String get removalBody;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid value.'**
  String get requiredField;

  /// No description provided for @family.
  ///
  /// In en, this message translates to:
  /// **'Family accounts'**
  String get family;

  /// No description provided for @profiles.
  ///
  /// In en, this message translates to:
  /// **'Viewing profiles'**
  String get profiles;

  /// No description provided for @createFamily.
  ///
  /// In en, this message translates to:
  /// **'Create a family'**
  String get createFamily;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite a member'**
  String get invite;

  /// No description provided for @newProfile.
  ///
  /// In en, this message translates to:
  /// **'New viewing profile'**
  String get newProfile;

  /// No description provided for @administrator.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get administrator;

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scan;

  /// No description provided for @scanHelp.
  ///
  /// In en, this message translates to:
  /// **'Position the iPlex QR code inside the camera view.'**
  String get scanHelp;

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'This code is invalid, expired or already used.'**
  String get invalidCode;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @lastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last connection'**
  String get lastSeen;

  /// No description provided for @up.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get up;

  /// No description provided for @down.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get down;

  /// No description provided for @left.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get left;

  /// No description provided for @right.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get right;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent to Player'**
  String get sent;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @credentialsHint.
  ///
  /// In en, this message translates to:
  /// **'Credentials are encrypted on the server and are never displayed after saving.'**
  String get credentialsHint;

  /// No description provided for @sourceReady.
  ///
  /// In en, this message translates to:
  /// **'Synchronized'**
  String get sourceReady;

  /// No description provided for @sourceQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting to synchronize'**
  String get sourceQueued;

  /// No description provided for @sourceSyncing.
  ///
  /// In en, this message translates to:
  /// **'Synchronizing'**
  String get sourceSyncing;

  /// No description provided for @sourceError.
  ///
  /// In en, this message translates to:
  /// **'Sync failed. Previous catalog preserved.'**
  String get sourceError;

  /// No description provided for @sourceFailure.
  ///
  /// In en, this message translates to:
  /// **'Failure'**
  String get sourceFailure;

  /// No description provided for @subscription.
  ///
  /// In en, this message translates to:
  /// **'Player subscription'**
  String get subscription;

  /// No description provided for @trialNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Your 7-day trial starts when you link your first TV.'**
  String get trialNotStarted;

  /// No description provided for @trialActive.
  ///
  /// In en, this message translates to:
  /// **'Free trial active'**
  String get trialActive;

  /// No description provided for @subscriptionActive.
  ///
  /// In en, this message translates to:
  /// **'Subscription active'**
  String get subscriptionActive;

  /// No description provided for @subscriptionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Subscription cancelled'**
  String get subscriptionCancelled;

  /// No description provided for @subscriptionExpired.
  ///
  /// In en, this message translates to:
  /// **'Subscription expired'**
  String get subscriptionExpired;

  /// No description provided for @subscriptionPending.
  ///
  /// In en, this message translates to:
  /// **'Subscription pending'**
  String get subscriptionPending;

  /// No description provided for @monthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthly;

  /// No description provided for @annual.
  ///
  /// In en, this message translates to:
  /// **'Annual'**
  String get annual;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @systemLanguage.
  ///
  /// In en, this message translates to:
  /// **'Device language'**
  String get systemLanguage;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get myProfile;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get help;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'iPlex manages your ecosystem. Playback takes place exclusively in iPlex Player on your TV.'**
  String get aboutBody;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get logout;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'You will be asked to sign in again. Remove family members before deleting an administrator account. Your data will be queued for permanent deletion.'**
  String get deleteAccountBody;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get favorite;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get more;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No matching content'**
  String get noResults;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get notFound;

  /// No description provided for @accessDenied.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission for this action.'**
  String get accessDenied;

  /// No description provided for @familyLimit.
  ///
  /// In en, this message translates to:
  /// **'This family already has five accounts.'**
  String get familyLimit;

  /// No description provided for @requiresLogin.
  ///
  /// In en, this message translates to:
  /// **'Please sign in again to continue.'**
  String get requiresLogin;

  /// No description provided for @appVerificationFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not verify this app with the server. Your session is still active; try again in a few minutes.'**
  String get appVerificationFailed;

  /// No description provided for @familyHasMembers.
  ///
  /// In en, this message translates to:
  /// **'Remove the family members before deleting your account.'**
  String get familyHasMembers;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @continueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue watching'**
  String get continueWatching;

  /// No description provided for @sessionLimit.
  ///
  /// In en, this message translates to:
  /// **'Three TVs are already in use: {devices}.'**
  String sessionLimit(String devices);

  /// No description provided for @profileInUse.
  ///
  /// In en, this message translates to:
  /// **'This profile is in use on {device}.'**
  String profileInUse(String device);

  /// No description provided for @itemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items} =1{1 item} other{{count} items}}'**
  String itemCount(int count);

  /// No description provided for @homeWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to iPlex'**
  String get homeWelcome;

  /// No description provided for @homeSetupBody.
  ///
  /// In en, this message translates to:
  /// **'Set up your devices and content sources to get started.'**
  String get homeSetupBody;

  /// No description provided for @catalogEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'This source has no content available yet. You can review your sources or link a TV.'**
  String get catalogEmptyBody;

  /// No description provided for @addDevice.
  ///
  /// In en, this message translates to:
  /// **'Add device'**
  String get addDevice;

  /// No description provided for @configureIptv.
  ///
  /// In en, this message translates to:
  /// **'Configure IPTV'**
  String get configureIptv;

  /// No description provided for @manageFamily.
  ///
  /// In en, this message translates to:
  /// **'Manage family accounts'**
  String get manageFamily;

  /// No description provided for @familyRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Create or join a family in Users to manage devices and profiles. Home and IPTV remain available.'**
  String get familyRequiredBody;

  /// No description provided for @memberSetupHint.
  ///
  /// In en, this message translates to:
  /// **'Your family administrator can add devices, profiles and content sources. You can browse the available information here.'**
  String get memberSetupHint;

  /// No description provided for @restoringSession.
  ///
  /// In en, this message translates to:
  /// **'Checking your session…'**
  String get restoringSession;

  /// No description provided for @loadingAccount.
  ///
  /// In en, this message translates to:
  /// **'Preparing your account…'**
  String get loadingAccount;

  /// No description provided for @sessionLoadError.
  ///
  /// In en, this message translates to:
  /// **'We could not prepare your session. Check your connection and try again.'**
  String get sessionLoadError;

  /// No description provided for @catalogPreparing.
  ///
  /// In en, this message translates to:
  /// **'Your sources are waiting to synchronize. Content will appear here when processing is complete.'**
  String get catalogPreparing;

  /// No description provided for @catalogSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not synchronize your catalog'**
  String get catalogSyncFailed;

  /// No description provided for @noResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Try another title or clear the search to see the available catalog.'**
  String get noResultsBody;

  /// No description provided for @unlinkedAccount.
  ///
  /// In en, this message translates to:
  /// **'No family linked'**
  String get unlinkedAccount;

  /// No description provided for @iptvSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your content sources'**
  String get iptvSubtitle;

  /// No description provided for @emptySourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'No IPTV sources'**
  String get emptySourcesTitle;

  /// No description provided for @emptySourcesDescription.
  ///
  /// In en, this message translates to:
  /// **'Add your first source to make content available in iPlex.'**
  String get emptySourcesDescription;

  /// No description provided for @addSource.
  ///
  /// In en, this message translates to:
  /// **'Add source'**
  String get addSource;

  /// No description provided for @editSource.
  ///
  /// In en, this message translates to:
  /// **'Edit source'**
  String get editSource;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @deleteSource.
  ///
  /// In en, this message translates to:
  /// **'Delete source'**
  String get deleteSource;

  /// No description provided for @confirmDeleteSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete IPTV source?'**
  String get confirmDeleteSourceTitle;

  /// No description provided for @confirmDeleteSourceBody.
  ///
  /// In en, this message translates to:
  /// **'This action will remove the source and linked contents from your catalog. Do you wish to continue?'**
  String get confirmDeleteSourceBody;

  /// No description provided for @lastSync.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {time}'**
  String lastSync(String time);

  /// No description provided for @neverSynced.
  ///
  /// In en, this message translates to:
  /// **'Never synchronized'**
  String get neverSynced;

  /// No description provided for @sourceType.
  ///
  /// In en, this message translates to:
  /// **'Source type'**
  String get sourceType;

  /// No description provided for @sourceFormatM3u.
  ///
  /// In en, this message translates to:
  /// **'M3U / M3U8'**
  String get sourceFormatM3u;

  /// No description provided for @sourceFormatXtream.
  ///
  /// In en, this message translates to:
  /// **'Xtream Codes'**
  String get sourceFormatXtream;

  /// No description provided for @sourceValidating.
  ///
  /// In en, this message translates to:
  /// **'Validating connection'**
  String get sourceValidating;

  /// No description provided for @sourceHost.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get sourceHost;

  /// No description provided for @catalogSummary.
  ///
  /// In en, this message translates to:
  /// **'Catalog contents'**
  String get catalogSummary;

  /// No description provided for @passwordKeepHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to keep current password'**
  String get passwordKeepHint;

  /// No description provided for @playlistUrl.
  ///
  /// In en, this message translates to:
  /// **'Playlist URL'**
  String get playlistUrl;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// No description provided for @managerAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Free iPlex Gestor'**
  String get managerAccessTitle;

  /// No description provided for @managerAccessBody.
  ///
  /// In en, this message translates to:
  /// **'Manage your family, profiles, devices and IPTV sources for free, even after your trial ends. Playback in iPlex Player requires a valid trial or subscription.'**
  String get managerAccessBody;

  /// No description provided for @subscriptionManagedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Your family subscription details are available to its administrator. You can consult the Player plans below.'**
  String get subscriptionManagedByAdmin;

  /// No description provided for @playbackSubscriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Playback requires a valid trial or subscription. Check the Player plans in Account.'**
  String get playbackSubscriptionRequired;

  /// No description provided for @sourceFormatUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get sourceFormatUrl;

  /// No description provided for @sourceFormatFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get sourceFormatFile;

  /// No description provided for @sourceFormatOtherM3u8.
  ///
  /// In en, this message translates to:
  /// **'Alternative M3U8'**
  String get sourceFormatOtherM3u8;

  /// No description provided for @sourceFile.
  ///
  /// In en, this message translates to:
  /// **'M3U / M3U8 File'**
  String get sourceFile;

  /// No description provided for @selectFile.
  ///
  /// In en, this message translates to:
  /// **'Select file'**
  String get selectFile;

  /// No description provided for @changeFile.
  ///
  /// In en, this message translates to:
  /// **'Replace file'**
  String get changeFile;

  /// No description provided for @noFileSelected.
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get noFileSelected;

  /// No description provided for @invalidFileFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid file format. Select a valid .m3u or .m3u8 file.'**
  String get invalidFileFormat;

  /// No description provided for @fileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'File exceeds the 20MB limit.'**
  String get fileTooLarge;

  /// No description provided for @epgUrl.
  ///
  /// In en, this message translates to:
  /// **'EPG URL (optional)'**
  String get epgUrl;

  /// No description provided for @protectPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Protect playlist'**
  String get protectPlaylist;

  /// No description provided for @protectPlaylistHint.
  ///
  /// In en, this message translates to:
  /// **'Require PIN to access this source'**
  String get protectPlaylistHint;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get pin;

  /// No description provided for @confirmPin.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get confirmPin;

  /// No description provided for @pinMustMatch.
  ///
  /// In en, this message translates to:
  /// **'PINs do not match.'**
  String get pinMustMatch;

  /// No description provided for @pinLengthError.
  ///
  /// In en, this message translates to:
  /// **'PIN must be between 4 and 6 digits.'**
  String get pinLengthError;

  /// No description provided for @pinRequired.
  ///
  /// In en, this message translates to:
  /// **'PIN is required when protection is enabled.'**
  String get pinRequired;

  /// No description provided for @enterPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Protected source'**
  String get enterPinTitle;

  /// No description provided for @enterPinBody.
  ///
  /// In en, this message translates to:
  /// **'Enter security PIN to access this source.'**
  String get enterPinBody;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @incorrectPin.
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN. {remaining} attempts remaining.'**
  String incorrectPin(int remaining);

  /// No description provided for @pinLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many failed attempts. Try again later.'**
  String get pinLocked;

  /// No description provided for @singleStream.
  ///
  /// In en, this message translates to:
  /// **'Individual stream'**
  String get singleStream;

  /// No description provided for @keepExistingPin.
  ///
  /// In en, this message translates to:
  /// **'Keep existing PIN'**
  String get keepExistingPin;

  /// No description provided for @changePin.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get changePin;

  /// No description provided for @fileKeepHint.
  ///
  /// In en, this message translates to:
  /// **'Leave unselected to keep current file'**
  String get fileKeepHint;

  /// No description provided for @otherM3u8Url.
  ///
  /// In en, this message translates to:
  /// **'Alternative M3U8 URL'**
  String get otherM3u8Url;

  /// No description provided for @confirmChangeFormatTitle.
  ///
  /// In en, this message translates to:
  /// **'Change source format?'**
  String get confirmChangeFormatTitle;

  /// No description provided for @confirmChangeFormatBody.
  ///
  /// In en, this message translates to:
  /// **'Changing the source format will require reconfiguring the source settings. Do you want to continue?'**
  String get confirmChangeFormatBody;

  /// No description provided for @invalidInput.
  ///
  /// In en, this message translates to:
  /// **'Review the fields and try saving again.'**
  String get invalidInput;

  /// No description provided for @connectionFailure.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the service. Check your connection and try again.'**
  String get connectionFailure;

  /// No description provided for @requestTimeout.
  ///
  /// In en, this message translates to:
  /// **'The request took longer than expected. Check whether the change was saved before trying again.'**
  String get requestTimeout;

  /// No description provided for @accountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not access your settings. Refresh the screen or sign in again.'**
  String get accountUnavailable;

  /// No description provided for @sourceCredentialsRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the source username and password.'**
  String get sourceCredentialsRequired;

  /// No description provided for @sourceUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid URL (HTTP or HTTPS) without spaces or credentials before the server address.'**
  String get sourceUrlInvalid;

  /// No description provided for @iptvKeepConnection.
  ///
  /// In en, this message translates to:
  /// **'Leave connection fields blank to keep the saved credentials and URLs. Enter a complete value to replace one.'**
  String get iptvKeepConnection;

  /// No description provided for @iptvRemoveEpg.
  ///
  /// In en, this message translates to:
  /// **'Remove saved EPG'**
  String get iptvRemoveEpg;

  /// No description provided for @iptvEpgConfigured.
  ///
  /// In en, this message translates to:
  /// **'EPG configured'**
  String get iptvEpgConfigured;

  /// No description provided for @iptvSourceConflict.
  ///
  /// In en, this message translates to:
  /// **'This source changed. Reopen the form before saving.'**
  String get iptvSourceConflict;

  /// No description provided for @iptvRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Please wait a moment before trying again.'**
  String get iptvRateLimited;

  /// No description provided for @iptvSourceLimit.
  ///
  /// In en, this message translates to:
  /// **'The limit of 100 sources has been reached.'**
  String get iptvSourceLimit;

  /// No description provided for @legal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legal;

  /// No description provided for @legalLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading document…'**
  String get legalLoading;

  /// No description provided for @legalErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Unable to load document.'**
  String get legalErrorGeneric;

  /// No description provided for @legalErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Check your internet connection and try again.'**
  String get legalErrorNetwork;

  /// No description provided for @legalErrorBlocked.
  ///
  /// In en, this message translates to:
  /// **'Navigation to this address is not allowed.'**
  String get legalErrorBlocked;

  /// No description provided for @syncSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'IPTV synced'**
  String get syncSuccessTitle;

  /// No description provided for @syncSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Your IPTV playlist has been successfully updated.'**
  String get syncSuccessBody;

  /// No description provided for @viewIptv.
  ///
  /// In en, this message translates to:
  /// **'View IPTV'**
  String get viewIptv;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @syncFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get syncFailureTitle;

  /// No description provided for @errorCannotConnect.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server.'**
  String get errorCannotConnect;

  /// No description provided for @errorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid credentials.'**
  String get errorInvalidCredentials;

  /// No description provided for @errorInvalidPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Invalid playlist.'**
  String get errorInvalidPlaylist;

  /// No description provided for @errorConnectionTimeout.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out.'**
  String get errorConnectionTimeout;

  /// No description provided for @errorTemporaryProcessing.
  ///
  /// In en, this message translates to:
  /// **'Temporary processing error.'**
  String get errorTemporaryProcessing;

  /// No description provided for @errorInvalidSourceUrl.
  ///
  /// In en, this message translates to:
  /// **'The IPTV address is invalid.'**
  String get errorInvalidSourceUrl;

  /// No description provided for @errorUnrecognizedSourceFormat.
  ///
  /// In en, this message translates to:
  /// **'Could not identify the IPTV format.'**
  String get errorUnrecognizedSourceFormat;

  /// No description provided for @errorProviderRateLimited.
  ///
  /// In en, this message translates to:
  /// **'The server is rate limiting requests. Please try again later.'**
  String get errorProviderRateLimited;

  /// No description provided for @errorProviderTimeBudget.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to respond.'**
  String get errorProviderTimeBudget;

  /// No description provided for @errorDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not download IPTV data.'**
  String get errorDownloadFailed;

  /// No description provided for @errorCatalogTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The playlist exceeds the allowed processing limit.'**
  String get errorCatalogTooLarge;

  /// No description provided for @errorSuspiciousCatalog.
  ///
  /// In en, this message translates to:
  /// **'The received playlist is empty or incomplete.'**
  String get errorSuspiciousCatalog;

  /// No description provided for @errorDuplicateContent.
  ///
  /// In en, this message translates to:
  /// **'The playlist contains duplicate content.'**
  String get errorDuplicateContent;

  /// No description provided for @errorHlsOriginRequired.
  ///
  /// In en, this message translates to:
  /// **'The HLS stream requires a valid origin address.'**
  String get errorHlsOriginRequired;

  /// No description provided for @errorParsingFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not parse the IPTV data.'**
  String get errorParsingFailed;

  /// No description provided for @errorNormalizationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare the catalog.'**
  String get errorNormalizationFailed;

  /// No description provided for @errorStorageUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not store the processed catalog.'**
  String get errorStorageUploadFailed;

  /// No description provided for @errorCatalogPublicationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not finalize the catalog update.'**
  String get errorCatalogPublicationFailed;

  /// No description provided for @errorCatalogSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the synchronization.'**
  String get errorCatalogSyncFailed;

  /// No description provided for @errorUnsafeProvider.
  ///
  /// In en, this message translates to:
  /// **'Address not allowed for security reasons.'**
  String get errorUnsafeProvider;

  /// No description provided for @deviceLinked.
  ///
  /// In en, this message translates to:
  /// **'Device linked'**
  String get deviceLinked;

  /// No description provided for @deviceLinkedBody.
  ///
  /// In en, this message translates to:
  /// **'The TV \"{name}\" is now linked.'**
  String deviceLinkedBody(String name);

  /// No description provided for @deviceAlreadyLinkedOtherFamily.
  ///
  /// In en, this message translates to:
  /// **'This TV is already linked to another family. Unlink it from its previous family before connecting here.'**
  String get deviceAlreadyLinkedOtherFamily;

  /// No description provided for @deviceAlreadyLinkedSameFamily.
  ///
  /// In en, this message translates to:
  /// **'This TV is already linked here.'**
  String get deviceAlreadyLinkedSameFamily;

  /// No description provided for @invalidQrCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR Code. Please check the code displayed on your TV.'**
  String get invalidQrCode;

  /// No description provided for @cameraPermissionHelp.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed to scan the QR Code on your TV. You can also enter the code manually.'**
  String get cameraPermissionHelp;

  /// No description provided for @pairingCompleted.
  ///
  /// In en, this message translates to:
  /// **'Pairing completed'**
  String get pairingCompleted;

  /// No description provided for @addDeviceInstructionsTitle.
  ///
  /// In en, this message translates to:
  /// **'How to connect your TV'**
  String get addDeviceInstructionsTitle;

  /// No description provided for @addDeviceStep1.
  ///
  /// In en, this message translates to:
  /// **'1. Open the iPlex Player app on your TV.'**
  String get addDeviceStep1;

  /// No description provided for @addDeviceStep2.
  ///
  /// In en, this message translates to:
  /// **'2. Wait for the QR code and pairing code to appear.'**
  String get addDeviceStep2;

  /// No description provided for @addDeviceStep3.
  ///
  /// In en, this message translates to:
  /// **'3. Scan the QR code with your camera or enter the code manually.'**
  String get addDeviceStep3;

  /// No description provided for @addDeviceStep4.
  ///
  /// In en, this message translates to:
  /// **'4. Confirm the device details to finish.'**
  String get addDeviceStep4;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// No description provided for @enterCodeManually.
  ///
  /// In en, this message translates to:
  /// **'Enter code manually'**
  String get enterCodeManually;

  /// No description provided for @enterCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter pairing code'**
  String get enterCodeTitle;

  /// No description provided for @enterCodeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 749-281'**
  String get enterCodeHint;

  /// No description provided for @enterCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code shown on your TV screen.'**
  String get enterCodeHelp;

  /// No description provided for @confirmPairingTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm device link'**
  String get confirmPairingTitle;

  /// No description provided for @tvNameLabel.
  ///
  /// In en, this message translates to:
  /// **'TV Name'**
  String get tvNameLabel;

  /// No description provided for @platformLabel.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platformLabel;

  /// No description provided for @manufacturerLabel.
  ///
  /// In en, this message translates to:
  /// **'Manufacturer'**
  String get manufacturerLabel;

  /// No description provided for @modelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelLabel;

  /// No description provided for @maskedIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get maskedIdLabel;

  /// No description provided for @confirmLinkButton.
  ///
  /// In en, this message translates to:
  /// **'Link device'**
  String get confirmLinkButton;

  /// No description provided for @cancelLinkButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelLinkButton;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get viewDetails;

  /// No description provided for @backToDevices.
  ///
  /// In en, this message translates to:
  /// **'Back to devices'**
  String get backToDevices;

  /// No description provided for @unlinkDevice.
  ///
  /// In en, this message translates to:
  /// **'Unlink device'**
  String get unlinkDevice;

  /// No description provided for @unlinkConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlink this TV?'**
  String get unlinkConfirmTitle;

  /// No description provided for @unlinkConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This TV will lose access to all family contents and will need to be paired again to reconnect.'**
  String get unlinkConfirmBody;

  /// No description provided for @editDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Edit TV Name'**
  String get editDeviceName;

  /// No description provided for @linkedAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Linked on'**
  String get linkedAtLabel;

  /// No description provided for @neverActive.
  ///
  /// In en, this message translates to:
  /// **'No activity recorded yet'**
  String get neverActive;

  /// No description provided for @publicUserCode.
  ///
  /// In en, this message translates to:
  /// **'User code'**
  String get publicUserCode;

  /// No description provided for @publicIdentityHelp.
  ///
  /// In en, this message translates to:
  /// **'Public identification for membership requests. This is not a password or a TV code.'**
  String get publicIdentityHelp;

  /// No description provided for @identityUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Identification unavailable. Please sign in again.'**
  String get identityUnavailable;

  /// No description provided for @copyPublicCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyPublicCode;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get codeCopied;

  /// No description provided for @publicIdentityScanHelp.
  ///
  /// In en, this message translates to:
  /// **'Scan the user QR code displayed on the iPlex Home screen.'**
  String get publicIdentityScanHelp;

  /// No description provided for @invalidPublicCode.
  ///
  /// In en, this message translates to:
  /// **'Enter a 12-character alphanumeric user code.'**
  String get invalidPublicCode;

  /// No description provided for @membershipRequests.
  ///
  /// In en, this message translates to:
  /// **'Membership requests'**
  String get membershipRequests;

  /// No description provided for @membershipAcceptHelp.
  ///
  /// In en, this message translates to:
  /// **'Accepting moves your account into this family. If your individual family has IPTV sources, devices or profiles, remove them first.'**
  String get membershipAcceptHelp;

  /// No description provided for @acceptMembership.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get acceptMembership;

  /// No description provided for @declineMembership.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get declineMembership;

  /// No description provided for @sendMembershipRequest.
  ///
  /// In en, this message translates to:
  /// **'Request membership'**
  String get sendMembershipRequest;

  /// No description provided for @membershipSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent. Awaiting acceptance.'**
  String get membershipSent;

  /// No description provided for @shareApplication.
  ///
  /// In en, this message translates to:
  /// **'Share application'**
  String get shareApplication;

  /// No description provided for @provisionalShareMessage.
  ///
  /// In en, this message translates to:
  /// **'Discover iPlex. The official installation link will be available soon.'**
  String get provisionalShareMessage;

  /// No description provided for @publicUserUnavailable.
  ///
  /// In en, this message translates to:
  /// **'User not found or unavailable for membership.'**
  String get publicUserUnavailable;

  /// No description provided for @membershipExpired.
  ///
  /// In en, this message translates to:
  /// **'This request has expired or is no longer available.'**
  String get membershipExpired;

  /// No description provided for @shareUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sharing is unavailable on this device.'**
  String get shareUnavailable;

  /// No description provided for @familyTitle.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get familyTitle;

  /// No description provided for @pairingExpired.
  ///
  /// In en, this message translates to:
  /// **'This TV code has expired or was already used. Wait for the TV to show a new one.'**
  String get pairingExpired;

  /// No description provided for @deviceLinkedElsewhere.
  ///
  /// In en, this message translates to:
  /// **'This TV is already linked to another account. Unlink it there first.'**
  String get deviceLinkedElsewhere;

  /// No description provided for @errorInvalidEpg.
  ///
  /// In en, this message translates to:
  /// **'The program guide (EPG) could not be read.'**
  String get errorInvalidEpg;

  /// No description provided for @errorCatalogIntegrity.
  ///
  /// In en, this message translates to:
  /// **'The generated catalog failed the integrity check. The previous catalog was kept.'**
  String get errorCatalogIntegrity;

  /// No description provided for @errorWorkerRetriesExhausted.
  ///
  /// In en, this message translates to:
  /// **'Synchronization failed after several attempts. Please try again later.'**
  String get errorWorkerRetriesExhausted;

  /// No description provided for @errorSourceSecretUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Saved credentials could not be read. Edit the source and enter them again.'**
  String get errorSourceSecretUnavailable;

  /// No description provided for @profileType.
  ///
  /// In en, this message translates to:
  /// **'Profile type'**
  String get profileType;

  /// No description provided for @profileTypeRegular.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get profileTypeRegular;

  /// No description provided for @profileTypeKids.
  ///
  /// In en, this message translates to:
  /// **'Kids'**
  String get profileTypeKids;

  /// No description provided for @profileTypeAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get profileTypeAdmin;

  /// No description provided for @profileTypeGuest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get profileTypeGuest;

  /// No description provided for @accountLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked to an account'**
  String get accountLinked;

  /// No description provided for @accountNotLinked.
  ///
  /// In en, this message translates to:
  /// **'No linked account'**
  String get accountNotLinked;

  /// No description provided for @linkAccount.
  ///
  /// In en, this message translates to:
  /// **'Link to an account'**
  String get linkAccount;

  /// No description provided for @unlinkAccount.
  ///
  /// In en, this message translates to:
  /// **'Unlink account'**
  String get unlinkAccount;

  /// No description provided for @unlinkAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlink account?'**
  String get unlinkAccountTitle;

  /// No description provided for @unlinkAccountBody.
  ///
  /// In en, this message translates to:
  /// **'The account will stop using {name}. The profile and its favorites, history, progress and permissions are kept.'**
  String unlinkAccountBody(String name);

  /// No description provided for @linkCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Link code'**
  String get linkCodeTitle;

  /// No description provided for @linkCodeBody.
  ///
  /// In en, this message translates to:
  /// **'On the person\'s account, open Family › Link to a profile and scan this QR code or type the code. Single use, valid for 10 minutes.'**
  String get linkCodeBody;

  /// No description provided for @allSpaces.
  ///
  /// In en, this message translates to:
  /// **'All spaces'**
  String get allSpaces;

  /// No description provided for @allSpacesHint.
  ///
  /// In en, this message translates to:
  /// **'Includes sources added later.'**
  String get allSpacesHint;

  /// No description provided for @spaceLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get spaceLive;

  /// No description provided for @spaceMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get spaceMovies;

  /// No description provided for @spaceSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get spaceSeries;

  /// No description provided for @kidsRestrictionNote.
  ///
  /// In en, this message translates to:
  /// **'Kids profiles only receive content identified as for children. This system restriction cannot be turned off.'**
  String get kidsRestrictionNote;

  /// No description provided for @adminFullAccess.
  ///
  /// In en, this message translates to:
  /// **'The administrator can access every space.'**
  String get adminFullAccess;

  /// No description provided for @noFamilySources.
  ///
  /// In en, this message translates to:
  /// **'This family has no IPTV sources.'**
  String get noFamilySources;

  /// No description provided for @clearFavorites.
  ///
  /// In en, this message translates to:
  /// **'Clear favorites'**
  String get clearFavorites;

  /// No description provided for @clearFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear favorites?'**
  String get clearFavoritesTitle;

  /// No description provided for @clearWatchedTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear watched history?'**
  String get clearWatchedTitle;

  /// No description provided for @clearWatchedBody.
  ///
  /// In en, this message translates to:
  /// **'All of {name}\'s watched history will be permanently deleted. This can\'t be undone. The deletion will sync to every device.'**
  String clearWatchedBody(String name);

  /// No description provided for @clearContinueWatching.
  ///
  /// In en, this message translates to:
  /// **'Clear Continue watching'**
  String get clearContinueWatching;

  /// No description provided for @clearProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Continue watching?'**
  String get clearProgressTitle;

  /// No description provided for @clearProgressBody.
  ///
  /// In en, this message translates to:
  /// **'All of {name}\'s saved playback progress will be permanently deleted. This can\'t be undone. The deletion will sync to every device.'**
  String clearProgressBody(String name);

  /// No description provided for @dataCleared.
  ///
  /// In en, this message translates to:
  /// **'Data deleted.'**
  String get dataCleared;

  /// No description provided for @guestHint.
  ///
  /// In en, this message translates to:
  /// **'The guest doesn\'t save favorites, history or progress.'**
  String get guestHint;

  /// No description provided for @linkToProfile.
  ///
  /// In en, this message translates to:
  /// **'Link to a profile'**
  String get linkToProfile;

  /// No description provided for @linkToProfileBody.
  ///
  /// In en, this message translates to:
  /// **'Type the code or scan the QR code shown by the family administrator.'**
  String get linkToProfileBody;

  /// No description provided for @linkCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get linkCode;

  /// No description provided for @profileLinked.
  ///
  /// In en, this message translates to:
  /// **'Your account is now linked to the profile.'**
  String get profileLinked;

  /// No description provided for @errorProfileLimit.
  ///
  /// In en, this message translates to:
  /// **'This family already has four members.'**
  String get errorProfileLimit;

  /// No description provided for @errorProfileTypeImmutable.
  ///
  /// In en, this message translates to:
  /// **'The profile type can\'t be changed.'**
  String get errorProfileTypeImmutable;

  /// No description provided for @errorAccountAlreadyLinked.
  ///
  /// In en, this message translates to:
  /// **'This account is already linked to a profile in this family.'**
  String get errorAccountAlreadyLinked;

  /// No description provided for @errorProfileAlreadyLinked.
  ///
  /// In en, this message translates to:
  /// **'This profile is already linked to an account.'**
  String get errorProfileAlreadyLinked;

  /// No description provided for @errorLinkCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired or was already used. Ask the administrator for a new one.'**
  String get errorLinkCodeExpired;

  /// No description provided for @errorClearInProgress.
  ///
  /// In en, this message translates to:
  /// **'A clear is already running for this profile.'**
  String get errorClearInProgress;

  /// No description provided for @errorClearFailed.
  ///
  /// In en, this message translates to:
  /// **'The deletion could not be completed. Try again; nothing will be duplicated.'**
  String get errorClearFailed;

  /// No description provided for @errorGuestNotPersisted.
  ///
  /// In en, this message translates to:
  /// **'The guest doesn\'t save data.'**
  String get errorGuestNotPersisted;

  /// No description provided for @errorAdministratorProtected.
  ///
  /// In en, this message translates to:
  /// **'The administrator profile can\'t be changed this way.'**
  String get errorAdministratorProtected;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @subscriptionsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions available soon.'**
  String get subscriptionsComingSoon;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @restorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get restorePurchases;

  /// No description provided for @manageSubscriptionPlay.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription on Google Play'**
  String get manageSubscriptionPlay;

  /// No description provided for @purchasePending.
  ///
  /// In en, this message translates to:
  /// **'Payment pending. Access starts once Google Play confirms it.'**
  String get purchasePending;

  /// No description provided for @purchaseVerifying.
  ///
  /// In en, this message translates to:
  /// **'Confirming the purchase with Google Play…'**
  String get purchaseVerifying;

  /// No description provided for @purchaseConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Subscription confirmed.'**
  String get purchaseConfirmed;

  /// No description provided for @purchaseCanceled.
  ///
  /// In en, this message translates to:
  /// **'Purchase cancelled. Nothing was charged.'**
  String get purchaseCanceled;

  /// No description provided for @storeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The store isn\'t available on this device.'**
  String get storeUnavailable;

  /// No description provided for @playbackSubscriptionNote.
  ///
  /// In en, this message translates to:
  /// **'The subscription unlocks playback in iPlex Player for the family. The Manager stays free.'**
  String get playbackSubscriptionNote;

  /// No description provided for @errorPaymentsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions aren\'t available yet.'**
  String get errorPaymentsDisabled;

  /// No description provided for @errorPurchaseInvalid.
  ///
  /// In en, this message translates to:
  /// **'The purchase couldn\'t be validated with Google Play.'**
  String get errorPurchaseInvalid;

  /// No description provided for @errorPurchaseAccount.
  ///
  /// In en, this message translates to:
  /// **'This purchase belongs to another account.'**
  String get errorPurchaseAccount;

  /// No description provided for @errorPurchaseUsed.
  ///
  /// In en, this message translates to:
  /// **'This purchase is already linked to another family.'**
  String get errorPurchaseUsed;

  /// No description provided for @watchOnTv.
  ///
  /// In en, this message translates to:
  /// **'Watch on TV'**
  String get watchOnTv;

  /// No description provided for @noTvLinked.
  ///
  /// In en, this message translates to:
  /// **'No linked TV'**
  String get noTvLinked;

  /// No description provided for @noTvLinkedBody.
  ///
  /// In en, this message translates to:
  /// **'Link a TV in Devices to start titles on it from here.'**
  String get noTvLinkedBody;

  /// No description provided for @tvNotReady.
  ///
  /// In en, this message translates to:
  /// **'Open iPlex on the TV and choose a profile to receive the request.'**
  String get tvNotReady;

  /// No description provided for @chooseEpisode.
  ///
  /// In en, this message translates to:
  /// **'Choose the episode'**
  String get chooseEpisode;

  /// No description provided for @seasonNumber.
  ///
  /// In en, this message translates to:
  /// **'Season {number}'**
  String seasonNumber(int number);

  /// No description provided for @episodeNumber.
  ///
  /// In en, this message translates to:
  /// **'E{number}'**
  String episodeNumber(String number);

  /// No description provided for @noEpisodes.
  ///
  /// In en, this message translates to:
  /// **'No episodes are available for this series yet.'**
  String get noEpisodes;

  /// No description provided for @sendingToTv.
  ///
  /// In en, this message translates to:
  /// **'Sending to {tv}…'**
  String sendingToTv(String tv);

  /// No description provided for @tvReceivedRequest.
  ///
  /// In en, this message translates to:
  /// **'{tv} received the request.'**
  String tvReceivedRequest(String tv);

  /// No description provided for @waitingTvConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmation on {tv}: something is already playing there.'**
  String waitingTvConfirmation(String tv);

  /// No description provided for @playingOnTv.
  ///
  /// In en, this message translates to:
  /// **'Playing on {tv}.'**
  String playingOnTv(String tv);

  /// No description provided for @openedOnTv.
  ///
  /// In en, this message translates to:
  /// **'Opened on {tv}. Choose the episode with the TV remote.'**
  String openedOnTv(String tv);

  /// No description provided for @tvKeptCurrent.
  ///
  /// In en, this message translates to:
  /// **'The TV kept the current playback.'**
  String get tvKeptCurrent;

  /// No description provided for @tvNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'Nobody confirmed on the TV. The current playback continues.'**
  String get tvNoAnswer;

  /// No description provided for @tvDidNotRespond.
  ///
  /// In en, this message translates to:
  /// **'The TV did not respond. Check that iPlex is open on it and try again.'**
  String get tvDidNotRespond;

  /// No description provided for @playRequestExpired.
  ///
  /// In en, this message translates to:
  /// **'The request expired before reaching the TV. Try again.'**
  String get playRequestExpired;

  /// No description provided for @playRequestSuperseded.
  ///
  /// In en, this message translates to:
  /// **'A newer request replaced this one.'**
  String get playRequestSuperseded;

  /// No description provided for @playRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'The TV could not play this title.'**
  String get playRequestFailed;

  /// No description provided for @contentNotAllowedOnTv.
  ///
  /// In en, this message translates to:
  /// **'This title is not available for the profile in use on the TV.'**
  String get contentNotAllowedOnTv;

  /// No description provided for @sourceProtectedOnTv.
  ///
  /// In en, this message translates to:
  /// **'This source is PIN-protected and cannot be played on the TV yet.'**
  String get sourceProtectedOnTv;

  /// No description provided for @streamUnavailableOnTv.
  ///
  /// In en, this message translates to:
  /// **'The IPTV source did not release this title now. Try again later.'**
  String get streamUnavailableOnTv;

  /// No description provided for @formatUnsupportedOnTv.
  ///
  /// In en, this message translates to:
  /// **'The TV cannot play the format of this title.'**
  String get formatUnsupportedOnTv;

  /// No description provided for @episodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose an episode to watch on the TV.'**
  String get episodeRequired;

  /// No description provided for @deviceNotFound.
  ///
  /// In en, this message translates to:
  /// **'This TV is no longer linked.'**
  String get deviceNotFound;

  /// No description provided for @tvDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tvDone;

  /// No description provided for @parentalControl.
  ///
  /// In en, this message translates to:
  /// **'Parental control'**
  String get parentalControl;

  /// No description provided for @parentalControlBody.
  ///
  /// In en, this message translates to:
  /// **'When the family has a kids profile, adult profiles only open on the TV with the parental PIN. The PIN is checked by the iPlex server.'**
  String get parentalControlBody;

  /// No description provided for @parentalPinConfigured.
  ///
  /// In en, this message translates to:
  /// **'Parental PIN set'**
  String get parentalPinConfigured;

  /// No description provided for @parentalPinMissing.
  ///
  /// In en, this message translates to:
  /// **'Parental PIN not set'**
  String get parentalPinMissing;

  /// No description provided for @parentalPinMissingKids.
  ///
  /// In en, this message translates to:
  /// **'There is a kids profile: adult profiles stay locked on the TV until you set the PIN.'**
  String get parentalPinMissingKids;

  /// No description provided for @setParentalPin.
  ///
  /// In en, this message translates to:
  /// **'Set PIN'**
  String get setParentalPin;

  /// No description provided for @changeParentalPin.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get changeParentalPin;

  /// No description provided for @removeParentalPin.
  ///
  /// In en, this message translates to:
  /// **'Remove PIN'**
  String get removeParentalPin;

  /// No description provided for @removeParentalPinBody.
  ///
  /// In en, this message translates to:
  /// **'While there is a kids profile, adult profiles will stay locked on the TV.'**
  String get removeParentalPinBody;

  /// No description provided for @parentalPinLength.
  ///
  /// In en, this message translates to:
  /// **'Use 4 digits.'**
  String get parentalPinLength;

  /// No description provided for @parentalPinSaved.
  ///
  /// In en, this message translates to:
  /// **'Parental PIN saved.'**
  String get parentalPinSaved;

  /// No description provided for @parentalPinRemoved.
  ///
  /// In en, this message translates to:
  /// **'Parental PIN removed.'**
  String get parentalPinRemoved;

  /// No description provided for @sourceRetrying.
  ///
  /// In en, this message translates to:
  /// **'Retrying automatically'**
  String get sourceRetrying;

  /// No description provided for @previousCatalogKept.
  ///
  /// In en, this message translates to:
  /// **'The previous catalog was kept.'**
  String get previousCatalogKept;

  /// No description provided for @technicalDetail.
  ///
  /// In en, this message translates to:
  /// **'Technical detail: {detail}'**
  String technicalDetail(String detail);

  /// No description provided for @catalogKinds.
  ///
  /// In en, this message translates to:
  /// **'{channels} live · {movies} movies · {series} series'**
  String catalogKinds(int channels, int movies, int series);

  /// No description provided for @homeRecentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recently searched'**
  String get homeRecentSearches;

  /// No description provided for @selectIptvSource.
  ///
  /// In en, this message translates to:
  /// **'Select IPTV source'**
  String get selectIptvSource;

  /// No description provided for @iptvSources.
  ///
  /// In en, this message translates to:
  /// **'IPTV sources'**
  String get iptvSources;

  /// No description provided for @homeNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get homeNowPlaying;

  /// No description provided for @homeFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get homeFavorites;

  /// No description provided for @homeReleases.
  ///
  /// In en, this message translates to:
  /// **'New releases'**
  String get homeReleases;

  /// No description provided for @homeContinueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue watching'**
  String get homeContinueWatching;

  /// No description provided for @homeRecentMovies.
  ///
  /// In en, this message translates to:
  /// **'Recently added movies'**
  String get homeRecentMovies;

  /// No description provided for @homeRecentSeries.
  ///
  /// In en, this message translates to:
  /// **'Recently added series'**
  String get homeRecentSeries;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Home is still empty'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Search live content, movies and series. What you favorite, save to your list or start watching shows up here.'**
  String get homeEmptyBody;

  /// No description provided for @exploreCatalog.
  ///
  /// In en, this message translates to:
  /// **'Explore the catalog'**
  String get exploreCatalog;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFromFavorites;

  /// No description provided for @liveChannel.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get liveChannel;

  /// No description provided for @onAirNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get onAirNow;

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get upNext;

  /// No description provided for @castLabel.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get castLabel;

  /// No description provided for @runtimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String runtimeMinutes(int minutes);

  /// No description provided for @seasonsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 season} other{{count} seasons}}'**
  String seasonsCount(int count);

  /// No description provided for @seasonEpisodeShort.
  ///
  /// In en, this message translates to:
  /// **'S{season}E{episode}'**
  String seasonEpisodeShort(int season, String episode);

  /// No description provided for @ageRatingLabel.
  ///
  /// In en, this message translates to:
  /// **'Rated {rating}'**
  String ageRatingLabel(String rating);

  /// No description provided for @invitePending.
  ///
  /// In en, this message translates to:
  /// **'Invitation pending'**
  String get invitePending;

  /// No description provided for @cancelInvitation.
  ///
  /// In en, this message translates to:
  /// **'Cancel invitation'**
  String get cancelInvitation;

  /// No description provided for @cancelInvitationBody.
  ///
  /// In en, this message translates to:
  /// **'The invitation will no longer be valid and the person will not be able to accept it.'**
  String get cancelInvitationBody;

  /// No description provided for @leaveFamily.
  ///
  /// In en, this message translates to:
  /// **'Leave family'**
  String get leaveFamily;

  /// No description provided for @leaveFamilyBody.
  ///
  /// In en, this message translates to:
  /// **'You return to your individual family. Your data is kept.'**
  String get leaveFamilyBody;

  /// No description provided for @errorAlreadyInFamily.
  ///
  /// In en, this message translates to:
  /// **'This account already belongs to a family.'**
  String get errorAlreadyInFamily;

  /// No description provided for @errorIndividualFamilyHasResources.
  ///
  /// In en, this message translates to:
  /// **'To join another family, first remove the IPTV sources, devices and profiles of your individual family.'**
  String get errorIndividualFamilyHasResources;

  /// No description provided for @errorFamilyExclusive.
  ///
  /// In en, this message translates to:
  /// **'Each account belongs to a single family.'**
  String get errorFamilyExclusive;

  /// No description provided for @homeWishlist.
  ///
  /// In en, this message translates to:
  /// **'Wishlist'**
  String get homeWishlist;

  /// No description provided for @addToWishlist.
  ///
  /// In en, this message translates to:
  /// **'Add to wishlist'**
  String get addToWishlist;

  /// No description provided for @removeFromWishlist.
  ///
  /// In en, this message translates to:
  /// **'Remove from wishlist'**
  String get removeFromWishlist;

  /// No description provided for @notAvailableToWatch.
  ///
  /// In en, this message translates to:
  /// **'Not available to watch in your IPTV catalog. You can still save it.'**
  String get notAvailableToWatch;

  /// No description provided for @filmography.
  ///
  /// In en, this message translates to:
  /// **'Filmography'**
  String get filmography;

  /// No description provided for @biography.
  ///
  /// In en, this message translates to:
  /// **'Biography'**
  String get biography;

  /// No description provided for @movieKind.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get movieKind;

  /// No description provided for @seriesKind.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get seriesKind;

  /// No description provided for @metadataUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Information about this title is unavailable right now.'**
  String get metadataUnavailable;

  /// No description provided for @personUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Information about this person is unavailable right now.'**
  String get personUnavailable;

  /// No description provided for @discoveryNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This profile only shows titles from your catalog.'**
  String get discoveryNotAllowed;

  /// No description provided for @errorContentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This title is not available for this profile.'**
  String get errorContentUnavailable;

  /// No description provided for @errorStaleLibrary.
  ///
  /// In en, this message translates to:
  /// **'Your lists were updated on another device. Try again.'**
  String get errorStaleLibrary;

  /// No description provided for @createdByLabel.
  ///
  /// In en, this message translates to:
  /// **'Created by {names}'**
  String createdByLabel(String names);

  /// No description provided for @andConjunction.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get andConjunction;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @restartLabel.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get restartLabel;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @searchTab.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTab;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @searchPageHint.
  ///
  /// In en, this message translates to:
  /// **'Movies, series, live, actors…'**
  String get searchPageHint;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterChannels.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get filterChannels;

  /// No description provided for @filterMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get filterMovies;

  /// No description provided for @filterSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get filterSeries;

  /// No description provided for @filterActors.
  ///
  /// In en, this message translates to:
  /// **'Actors'**
  String get filterActors;

  /// No description provided for @myIplex.
  ///
  /// In en, this message translates to:
  /// **'My iPlex'**
  String get myIplex;

  /// No description provided for @recentSearchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearchesTitle;

  /// No description provided for @actorKind.
  ///
  /// In en, this message translates to:
  /// **'Actor'**
  String get actorKind;

  /// No description provided for @channelKind.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get channelKind;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @favoriteLabel.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favoriteLabel;

  /// No description provided for @wishlistLabel.
  ///
  /// In en, this message translates to:
  /// **'Wishlist'**
  String get wishlistLabel;

  /// No description provided for @infoTitle.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get infoTitle;

  /// No description provided for @genresLabel.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get genresLabel;

  /// No description provided for @directionLabel.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get directionLabel;

  /// No description provided for @ratingRowLabel.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get ratingRowLabel;

  /// No description provided for @runtimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get runtimeLabel;

  /// No description provided for @releaseYearLabel.
  ///
  /// In en, this message translates to:
  /// **'Release year'**
  String get releaseYearLabel;

  /// No description provided for @ageRatingRowLabel.
  ///
  /// In en, this message translates to:
  /// **'Age rating'**
  String get ageRatingRowLabel;

  /// No description provided for @originalTitleRow.
  ///
  /// In en, this message translates to:
  /// **'Original title'**
  String get originalTitleRow;

  /// No description provided for @youMayLike.
  ///
  /// In en, this message translates to:
  /// **'You may also like'**
  String get youMayLike;

  /// No description provided for @aboutTab.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTab;

  /// No description provided for @castTab.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get castTab;

  /// No description provided for @seasonsTab.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get seasonsTab;

  /// No description provided for @filmographyTab.
  ///
  /// In en, this message translates to:
  /// **'Filmography'**
  String get filmographyTab;

  /// No description provided for @noTvConnected.
  ///
  /// In en, this message translates to:
  /// **'No TV'**
  String get noTvConnected;

  /// No description provided for @deptActing.
  ///
  /// In en, this message translates to:
  /// **'Acting'**
  String get deptActing;

  /// No description provided for @deptDirecting.
  ///
  /// In en, this message translates to:
  /// **'Directing'**
  String get deptDirecting;

  /// No description provided for @deptWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing'**
  String get deptWriting;

  /// No description provided for @deptProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get deptProduction;

  /// No description provided for @seeDetails.
  ///
  /// In en, this message translates to:
  /// **'See details'**
  String get seeDetails;

  /// No description provided for @selectDevice.
  ///
  /// In en, this message translates to:
  /// **'Select a device'**
  String get selectDevice;

  /// No description provided for @connectedStatus.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectedStatus;

  /// No description provided for @availableStatus.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get availableStatus;

  /// No description provided for @removeFromContinueWatching.
  ///
  /// In en, this message translates to:
  /// **'Remove from Continue watching'**
  String get removeFromContinueWatching;

  /// No description provided for @neverOnline.
  ///
  /// In en, this message translates to:
  /// **'Never on'**
  String get neverOnline;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleKids.
  ///
  /// In en, this message translates to:
  /// **'Kids'**
  String get roleKids;

  /// No description provided for @roleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get roleMember;

  /// No description provided for @roleGuest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get roleGuest;

  /// No description provided for @kidsAccount.
  ///
  /// In en, this message translates to:
  /// **'Child account'**
  String get kidsAccount;

  /// No description provided for @addMember.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get addMember;

  /// No description provided for @guestAccount.
  ///
  /// In en, this message translates to:
  /// **'Guest account'**
  String get guestAccount;

  /// No description provided for @guestAccountHint.
  ///
  /// In en, this message translates to:
  /// **'Settings are kept when turned off.'**
  String get guestAccountHint;

  /// No description provided for @invitePendingShort.
  ///
  /// In en, this message translates to:
  /// **'Invitation pending'**
  String get invitePendingShort;

  /// No description provided for @adultContent.
  ///
  /// In en, this message translates to:
  /// **'Adult content'**
  String get adultContent;

  /// No description provided for @adultContentHint.
  ///
  /// In en, this message translates to:
  /// **'Titles and channels marked as adult.'**
  String get adultContentHint;

  /// No description provided for @adminLimitsTitle.
  ///
  /// In en, this message translates to:
  /// **'Access limits'**
  String get adminLimitsTitle;

  /// No description provided for @adminLimitsHint.
  ///
  /// In en, this message translates to:
  /// **'The member can restrict these further, never widen them.'**
  String get adminLimitsHint;

  /// No description provided for @myPreferences.
  ///
  /// In en, this message translates to:
  /// **'My preferences'**
  String get myPreferences;

  /// No description provided for @myPreferencesHint.
  ///
  /// In en, this message translates to:
  /// **'Only within what the administrator allows.'**
  String get myPreferencesHint;

  /// No description provided for @notAllowedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Not allowed by the administrator'**
  String get notAllowedByAdmin;

  /// No description provided for @personalPin.
  ///
  /// In en, this message translates to:
  /// **'Personal PIN'**
  String get personalPin;

  /// No description provided for @personalPinOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get personalPinOn;

  /// No description provided for @personalPinOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get personalPinOff;

  /// No description provided for @personalPinHint.
  ///
  /// In en, this message translates to:
  /// **'Protects your profile. Only you can set or change it.'**
  String get personalPinHint;

  /// No description provided for @enablePersonalPin.
  ///
  /// In en, this message translates to:
  /// **'Turn on PIN'**
  String get enablePersonalPin;

  /// No description provided for @changePersonalPin.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get changePersonalPin;

  /// No description provided for @disablePersonalPin.
  ///
  /// In en, this message translates to:
  /// **'Turn off PIN'**
  String get disablePersonalPin;

  /// No description provided for @currentPinLabel.
  ///
  /// In en, this message translates to:
  /// **'Current PIN'**
  String get currentPinLabel;

  /// No description provided for @newPinLabel.
  ///
  /// In en, this message translates to:
  /// **'New PIN (4 digits)'**
  String get newPinLabel;

  /// No description provided for @personalPinSaved.
  ///
  /// In en, this message translates to:
  /// **'PIN updated.'**
  String get personalPinSaved;

  /// No description provided for @personalPinRemoved.
  ///
  /// In en, this message translates to:
  /// **'PIN turned off.'**
  String get personalPinRemoved;

  /// No description provided for @watchedHistory.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get watchedHistory;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// No description provided for @emptyKind.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get emptyKind;

  /// No description provided for @minutesLeft.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min left'**
  String minutesLeft(int minutes);

  /// No description provided for @lastSyncLabel.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {time}'**
  String lastSyncLabel(String time);

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSection;

  /// No description provided for @securitySection.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securitySection;

  /// No description provided for @removeFromFamily.
  ///
  /// In en, this message translates to:
  /// **'Remove from family'**
  String get removeFromFamily;

  /// No description provided for @removeFromFamilyBody.
  ///
  /// In en, this message translates to:
  /// **'{name} goes back to their own family. The profile and its data stay here.'**
  String removeFromFamilyBody(String name);

  /// No description provided for @deleteProfile.
  ///
  /// In en, this message translates to:
  /// **'Delete profile'**
  String get deleteProfile;

  /// No description provided for @clearFavoritesAndWishlistBody.
  ///
  /// In en, this message translates to:
  /// **'All favorites and the wishlist of {name} will be permanently deleted (they are one library). This cannot be undone.'**
  String clearFavoritesAndWishlistBody(String name);

  /// No description provided for @errorPinInvalid.
  ///
  /// In en, this message translates to:
  /// **'Incorrect current PIN.'**
  String get errorPinInvalid;

  /// No description provided for @errorBeyondLimit.
  ///
  /// In en, this message translates to:
  /// **'This goes beyond what the administrator allows.'**
  String get errorBeyondLimit;

  /// No description provided for @errorProfileNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Your account is not linked to a profile in this family.'**
  String get errorProfileNotLinked;

  /// No description provided for @trialPlan.
  ///
  /// In en, this message translates to:
  /// **'7-day trial'**
  String get trialPlan;

  /// No description provided for @trialPlanBody.
  ///
  /// In en, this message translates to:
  /// **'Starts when the first TV is linked.'**
  String get trialPlanBody;

  /// No description provided for @lifetime.
  ///
  /// In en, this message translates to:
  /// **'Lifetime'**
  String get lifetime;

  /// No description provided for @lifetimeViaCoupon.
  ///
  /// In en, this message translates to:
  /// **'Unlocked with a coupon'**
  String get lifetimeViaCoupon;

  /// No description provided for @subscriptionLifetime.
  ///
  /// In en, this message translates to:
  /// **'Lifetime access'**
  String get subscriptionLifetime;

  /// No description provided for @couponCode.
  ///
  /// In en, this message translates to:
  /// **'Coupon code'**
  String get couponCode;

  /// No description provided for @redeemCoupon.
  ///
  /// In en, this message translates to:
  /// **'Redeem coupon'**
  String get redeemCoupon;

  /// No description provided for @couponRedeemed.
  ///
  /// In en, this message translates to:
  /// **'Coupon redeemed. Lifetime access unlocked.'**
  String get couponRedeemed;

  /// No description provided for @errorCouponInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid coupon.'**
  String get errorCouponInvalid;

  /// No description provided for @errorCouponExpired.
  ///
  /// In en, this message translates to:
  /// **'This coupon has expired.'**
  String get errorCouponExpired;

  /// No description provided for @errorCouponUsed.
  ///
  /// In en, this message translates to:
  /// **'This coupon has reached its usage limit.'**
  String get errorCouponUsed;

  /// No description provided for @errorAlreadyLifetime.
  ///
  /// In en, this message translates to:
  /// **'This family already has lifetime access.'**
  String get errorAlreadyLifetime;

  /// No description provided for @helpSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search questions and answers'**
  String get helpSearchHint;

  /// No description provided for @helpNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No answers found'**
  String get helpNoResultsTitle;

  /// No description provided for @helpNoResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Try other words or clear the search to see every question.'**
  String get helpNoResultsBody;

  /// No description provided for @contentSection.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get contentSection;

  /// No description provided for @contentChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get contentChannels;

  /// No description provided for @lastSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Last sync'**
  String get lastSyncTitle;

  /// No description provided for @clearFavoritesBody.
  ///
  /// In en, this message translates to:
  /// **'All of {name}\'s favorites will be permanently deleted. This cannot be undone. The deletion is synced to every device.'**
  String clearFavoritesBody(String name);

  /// No description provided for @clearWishlist.
  ///
  /// In en, this message translates to:
  /// **'Clear wishlist'**
  String get clearWishlist;

  /// No description provided for @clearWishlistTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear wishlist?'**
  String get clearWishlistTitle;

  /// No description provided for @clearWishlistBody.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s whole wishlist will be permanently deleted. This cannot be undone. The deletion is synced to every device.'**
  String clearWishlistBody(String name);

  /// Home tab with the adult content (only for profiles allowed to see it).
  ///
  /// In en, this message translates to:
  /// **'Adult'**
  String get adultTab;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
