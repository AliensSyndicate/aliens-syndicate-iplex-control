import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

Future<bool> initializeServices() async {
  const apiKey = String.fromEnvironment('FIREBASE_API_KEY'),
      appId = String.fromEnvironment('FIREBASE_APP_ID'),
      sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
      project = String.fromEnvironment(
        'FIREBASE_PROJECT_ID',
        defaultValue: 'iplex-2c8fc',
      ),
      emulator = bool.fromEnvironment('USE_EMULATORS');
  if (project != 'iplex-2c8fc' &&
      !(kDebugMode && emulator && project == 'demo-iplex')) {
    return false;
  }
  if (emulator && !kDebugMode) return false;
  try {
    FirebaseOptions options;
    if (apiKey.isNotEmpty && appId.isNotEmpty && sender.isNotEmpty) {
      options = FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: sender,
        projectId: project,
        storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
        iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
        authDomain: '$project.firebaseapp.com',
      );
    } else {
      options = DefaultFirebaseOptions.currentPlatform;
      // Emulator runs must address the demo project the emulators serve,
      // never the production project bundled in firebase_options.dart.
      if (emulator) options = options.copyWith(projectId: project);
    }
    await Firebase.initializeApp(options: options);
    // Family data is deliberately not persisted to a cross-account disk cache.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    if (emulator) {
      const host = String.fromEnvironment(
        'EMULATOR_HOST',
        defaultValue: '127.0.0.1',
      );
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      FirebaseFunctions.instanceFor(region: 'us-central1')
          .useFunctionsEmulator(host, 5001);
      // Debug + emulator only: lets simulators without a Google/Apple account
      // reach Home. Release builds never get here (see the guard above).
      if (const bool.fromEnvironment('EMULATOR_TEST_SIGN_IN') &&
          FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } else {
      try {
        // Debug builds only. No token ships in source: pass one registered in
        // App Check with --dart-define=APP_CHECK_DEBUG_TOKEN, or let the SDK
        // generate a per-install token (printed in the log) and register it.
        const debugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');
        const appCheckDebugToken = debugToken == '' ? null : debugToken;
        await FirebaseAppCheck.instance.activate(
          providerAndroid: kDebugMode
              ? const AndroidDebugProvider(debugToken: appCheckDebugToken)
              : const AndroidPlayIntegrityProvider(),
          providerApple: kDebugMode
              ? const AppleDebugProvider(debugToken: appCheckDebugToken)
              : const AppleAppAttestWithDeviceCheckFallbackProvider(),
          providerWeb:
              kIsWeb &&
                  const String.fromEnvironment('APP_CHECK_WEB_KEY').isNotEmpty
              ? ReCaptchaV3Provider(
                  const String.fromEnvironment('APP_CHECK_WEB_KEY'),
                )
              : null,
        );
      } catch (e) {
        debugPrint('FirebaseAppCheck activation skipped or failed: $e');
      }
      try {
        await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
      } catch (_) {}
      if (!kIsWeb) {
        try {
          await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
            kReleaseMode,
          );
          FlutterError.onError = (details) {
            FlutterError.presentError(details);
            FirebaseCrashlytics.instance.recordError(
              'flutter-error',
              details.stack,
              fatal: true,
            );
          };
          PlatformDispatcher.instance.onError = (error, stack) {
            FirebaseCrashlytics.instance.recordError(
              'unhandled-error',
              stack,
              fatal: true,
            );
            return true;
          };
        } catch (_) {}
      }
    }
    return true;
  } catch (e, stack) {
    debugPrint('Firebase initializeServices failed: $e\n$stack');
    return false;
  }
}
