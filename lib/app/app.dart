import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/design_system/components.dart';
import '../features/iptv/presentation/controllers/iptv_notification_controller.dart';
import '../features/iptv/presentation/widgets/global_iptv_sync_progress.dart';
import '../l10n/generated/app_localizations.dart';
import 'router.dart';

Locale resolveLocale(List<Locale>? locales) {
  for (final locale in locales ?? const <Locale>[]) {
    if (locale.languageCode == 'pt') return const Locale('pt', 'BR');
    if (locale.languageCode == 'es') return const Locale('es');
    if (locale.languageCode == 'en') return const Locale('en');
  }
  return const Locale('en');
}

class IplexApp extends ConsumerWidget {
  const IplexApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(iptvNotificationControllerProvider);
    final pref = ref.watch(accountProvider).value?.locale ?? 'system';
    final locale = pref == 'system'
        ? null
        : pref == 'pt_BR'
        ? const Locale('pt', 'BR')
        : Locale(pref);
    return MaterialApp.router(
      title: 'iPlex',
      debugShowCheckedModeBanner: false,
      theme: AppTokens.theme,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
        child: GraphiteBackdrop(
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              Positioned(
                top: MediaQuery.paddingOf(context).top,
                left: 0,
                right: 0,
                child: const GlobalIptvSyncProgress(),
              ),
            ],
          ),
        ),
      ),
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en'), Locale('pt', 'BR'), Locale('es')],
      locale: locale,
      localeListResolutionCallback: (locales, _) => resolveLocale(locales),
    );
  }
}
