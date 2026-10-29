import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/data/firebase_repository.dart';
import 'core/data/providers.dart';
import 'core/design_system/components.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // The native splash (logo) stays until the app is ready to draw its
  // loading page: no empty screen while the services start.
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  // Home artwork stays decoded in memory (and on disk) while the user scrolls
  // rows and moves between tabs, instead of being fetched again.
  configureImageCache();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  final configured = await initializeServices();
  runApp(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(
          FirebaseManagerRepository(configured: configured),
        ),
      ],
      // Only the native splash (with the logo) before the first frame; then
      // the loading page and, all set, Home.
      child: const IplexApp(),
    ),
  );
  FlutterNativeSplash.remove();
}
