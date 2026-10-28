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

/// Only public item IDs are stored locally. readHome resolves them against the
/// current catalog and permissions before any title is displayed again.
class RecentSearchNotifier extends Notifier<List<String>> {
  String? _key;
  Future<void> _restored = Future.value();
  Future<void> _writes = Future.value();

  @override
  List<String> build() {
    final account = ref.watch(accountProvider).asData?.value;
    final scope = account?.iptvScopeId;
    final key = _key = account == null || scope == null
        ? null
        : 'iplex.home.recentSearch.${account.uid}.$scope';
    _restored = key == null ? Future.value() : _restore(key);
    return const [];
  }

  Future<void> _restore(String key) async {
    try {
      final prefs = await ref.read(preferencesProvider.future);
      final saved = await prefs.getStringList(key) ?? const <String>[];
      if (ref.mounted && _key == key) {
        state = saved.toSet().take(10).toList();
      }
    } catch (_) {
      // Local history is optional; search still works if storage is unavailable.
    }
  }

  Future<void> record(String id) async {
    final key = _key;
    if (key == null) return;
    await _restored;
    if (!ref.mounted || key != _key) return;
    final ids = [id, ...state.where((saved) => saved != id)].take(10).toList();
    state = ids;
    _writes = _writes.then((_) async {
      try {
        await (await ref.read(preferencesProvider.future))
            .setStringList(key, ids);
      } catch (_) {
        // Keep the session's history even if persistence fails.
      }
    });
    await _writes;
  }
}

final recentSearchProvider =
    NotifierProvider<RecentSearchNotifier, List<String>>(
      RecentSearchNotifier.new,
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
  // A finished (re)sync publishes a new catalog version: reload the rows
  // without the user having to leave and re-enter the Home.
  ref.watch(
    entriesProvider('sources').select(
      (sources) => [
        for (final s in sources.asData?.value ?? const <Entry>[])
          if (sourceId == null || s.id == sourceId) s.text('version'),
      ].join(','),
    ),
  );
  final recentSearchIds = ref.watch(recentSearchProvider);
  final result = await ref
      .watch(repositoryProvider)
      .mutate('readHome', {
        'sourceId': sourceId,
        if (recentSearchIds.isNotEmpty) 'recentSearchIds': recentSearchIds,
      })
      .timeout(const Duration(seconds: 30));
  return HomeData.fromJson(await withWatched(ref, result, homeRow));
}, retry: (retryCount, error) => null);

/// Cards per Home row.
const homeRow = 10;

/// Older backends have no Assistidos in readHome: it comes from the
/// profile's own library (readProfileLibrary, same visibility rules). Best
/// effort: without it the row is simply not shown.
Future<Map<String, dynamic>> withWatched(
  Ref ref,
  Map<String, dynamic> home,
  int limit,
) async {
  final profile = home['profile'];
  if (home.containsKey('watched') ||
      profile is! Map ||
      profile['id'] is! String ||
      profile['type'] == 'guest') {
    return home;
  }
  try {
    final library = await ref
        .read(repositoryProvider)
        .mutate('readProfileLibrary', {'profileId': profile['id']})
        .timeout(const Duration(seconds: 30));
    final watched = [
      for (final raw in (library['watched'] as List? ?? const []))
        if (raw is Map && raw['id'] is String) Map<String, dynamic>.from(raw),
    ];
    // One per title, movies and series, never adult (the Meu iPlex rule).
    final rows = meuIplex([
      for (final raw in watched) Entry(raw['id'] as String, raw),
    ]).take(limit);
    return {
      ...home,
      'watched': [for (final e in rows) e.data],
    };
  } catch (_) {
    return home;
  }
}

/// "Ver tudo": one Home section returned whole by readHome (same source,
/// scope and visibility rules as the Home itself).
final homeSectionProvider = FutureProvider.autoDispose
    .family<HomeData, (HomeSection, String?)>((ref, key) async {
      final (section, sourceId) = key;
      ref.watch(accountProvider.select((a) => a.asData?.value?.iptvScopeId));
      final recentSearchIds = ref.watch(recentSearchProvider);
      final result = await ref
          .watch(repositoryProvider)
          .mutate('readHome', {
            'sourceId': sourceId,
            'section': section.name,
            if (recentSearchIds.isNotEmpty) 'recentSearchIds': recentSearchIds,
          })
          .timeout(const Duration(seconds: 30));
      return HomeData.fromJson(
        await withWatched(
          ref,
          result,
          section == HomeSection.watched ? 100 : homeRow,
        ),
      );
    }, retry: (retryCount, error) => null);
