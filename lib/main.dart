import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/splash_gate.dart';
import 'core/data/firebase_repository.dart';
import 'core/data/providers.dart';
import 'core/design_system/components.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      child: const SplashGate(child: IplexApp()),
    ),
  );
}
