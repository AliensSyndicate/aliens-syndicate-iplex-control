import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/data/providers.dart';
import '../../core/domain/models.dart';
import 'home_data.dart';

/// Device storage for small UI preferences (overridable in tests).
final preferencesProvider = FutureProvider<SharedPreferencesAsync>(
  (ref) async => SharedPreferencesAsync(),
  retry: (retryCount, error) => null,
);

/// IPTV source chosen on the Home, per account and scope. Kept while the user
/// navigates and across app restarts; a source that disappears falls back to
/// the first available one (see [effectiveSourceId]).
class SelectedSourceNotifier extends Notifier<String?> {
  String? _key;

  @override
  String? build() {
    final account = ref.watch(accountProvider).asData?.value;
    final scope = account?.iptvScopeId;
    _key = account == null || scope == null
        ? null
        : 'iplex.home.source.${account.uid}.$scope';
    final key = _key;
    if (key != null) {
      ref.watch(preferencesProvider.future).then((prefs) async {
        final saved = await prefs.getString(key);
        if (_key == key && state == null && saved != null) state = saved;
      }).ignore();
    }
    return null;
  }

  Future<void> select(String sourceId) async {
    state = sourceId;
    final key = _key;
    if (key == null) return;
    try {
      await (await ref.read(preferencesProvider.future))
          .setString(key, sourceId);
    } catch (_) {
      // Preference only: the selection still holds for this session.
    }
  }
}

final selectedSourceProvider =
    NotifierProvider<SelectedSourceNotifier, String?>(
      SelectedSourceNotifier.new,
    );

/// The selected source if it is still available, otherwise the first one.
String? effectiveSourceId(String? selected, List<Entry> ready) {
  final ids = [for (final e in ready) e.id];
  if (selected != null && ids.contains(selected)) return selected;
  return ids.isEmpty ? null : ids.first;
}

/// Home rows for the selected source (readHome). Refreshed on pull, after a
/// favorite change and whenever the source or the account scope changes.
final homeProvider = FutureProvider.autoDispose.family<HomeData, String?>((
  ref,
  sourceId,
) async {
  ref.watch(accountProvider.select((a) => a.asData?.value?.iptvScopeId));
  final result = await ref
      .watch(repositoryProvider)
      .mutate('readHome', {'sourceId': sourceId})
      .timeout(const Duration(seconds: 30));
  return HomeData.fromJson(result);
}, retry: (retryCount, error) => null);
