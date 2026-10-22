import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/firebase_repository.dart';
import '../core/data/providers.dart';
import '../features/home/home_providers.dart';

/// How often the app reports that the account is on, and how long after the
/// last report a member still shows as "ligado" on the Family screen.
const presenceInterval = Duration(minutes: 2);
const presenceWindow = Duration(minutes: 5);

/// Coming back after at least this long refreshes the Home, so the saved
/// progress (written by a TV meanwhile) is current without a pull.
const progressRefreshAfter = Duration(seconds: 30);

/// A member is on when the app reported within [presenceWindow].
bool memberOnline(num lastActiveAt, DateTime now) =>
    lastActiveAt > 0 &&
    now.millisecondsSinceEpoch - lastActiveAt < presenceWindow.inMilliseconds;

/// Reports the account presence (`touchPresence`) while the app is in the
/// foreground: on open, on resume and every [presenceInterval].
class PresenceReporter extends ConsumerStatefulWidget {
  const PresenceReporter({super.key});
  @override
  ConsumerState<PresenceReporter> createState() => _PresenceReporterState();
}

class _PresenceReporterState extends ConsumerState<PresenceReporter>
    with WidgetsBindingObserver {
  Timer? timer;
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  void start() {
    timer?.cancel();
    report();
    timer = Timer.periodic(presenceInterval, (_) => report());
  }

  Future<void> report() async {
    final repository = ref.read(repositoryProvider);
    // Only the real backend (test doubles keep their own action log).
    if (repository is! FirebaseManagerRepository) return;
    if (ref.read(accountProvider).asData?.value?.familyId == null) return;
    try {
      await repository.mutate('touchPresence');
    } catch (_) {
      // Presence is best effort: never interrupts the app.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      start();
      final since = pausedAt;
      pausedAt = null;
      if (since != null &&
          DateTime.now().difference(since) >= progressRefreshAfter) {
        ref.invalidate(homeProvider);
      }
    } else if (state == AppLifecycleState.paused) {
      pausedAt = DateTime.now();
      timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Report as soon as the family is known (first sign-in, joining one).
    ref.listen(accountProvider.select((a) => a.asData?.value?.familyId), (
      previous,
      next,
    ) {
      if (next != null && next != previous) report();
    });
    return const SizedBox.shrink();
  }
}
