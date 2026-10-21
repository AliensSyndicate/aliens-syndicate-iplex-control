import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/splash_gate.dart';
import 'core/data/firebase_repository.dart';
import 'core/data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Home artwork (posters/logos) stays decoded in memory while the user
  // scrolls rows and moves between tabs, instead of being fetched again.
  PaintingBinding.instance.imageCache
    ..maximumSize = 1500
    ..maximumSizeBytes = 256 << 20;
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
