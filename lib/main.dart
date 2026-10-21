import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/data/firebase_repository.dart';
import 'core/data/providers.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
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
  // Keep the native splash visible for a minimum time so it is actually seen.
  final minimumSplash = Future<void>.delayed(const Duration(milliseconds: 1500));
  final configured = await initializeServices();
  await minimumSplash;
  runApp(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(
          FirebaseManagerRepository(configured: configured),
        ),
      ],
      child: const IplexApp(),
    ),
  );
  FlutterNativeSplash.remove();
}
