import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/domain/models.dart';
import 'category_labels.dart';
import 'home_data.dart';

/// Records of one catalog set of a source, read as the TV reads them
/// (`readCatalogManifest` + `readCatalogChunk`, filtered for the profile by
/// the backend): the items and the provider's category names by id.
@immutable
class CatalogSet {
  const CatalogSet(this.items, this.categoryNames);
  final List<Entry> items;
  final Map<String, String> categoryNames;
}

/// Item and category sets of a tab kind (`adult`: every adult item).
const _sets = {
  'channel': ('live', 'live_categories'),
  'movie': ('vod', 'vod_categories'),
  'series': ('series', 'series_categories'),
  'adult': ('adult', 'adult_categories'),
};

/// Chunks read at the same time.
const _parallelChunks = 8;

/// Device copy of the sets, as the TV keeps its own: one file per account,
/// source, version and profile view (the manifest's `viewerKey` changes when
/// the profile's permissions do), so a list is only downloaded again when
/// it or the permissions change.
Future<Directory?> _cacheDir() async {
  if (_testing) return null;
  try {
    final base = await getApplicationSupportDirectory();
    return await Directory('${base.path}/catalog_sets').create(recursive: true);
  } catch (_) {
    return null; // No cache (tests, restricted storage): always downloads.
  }
}

String _safe(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

CatalogSet _decodeSet(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  return _buildSet(
    (json['records'] as List).cast<Map>(),
    (json['categories'] as List).cast<Map>(),
  );
}

/// Widget tests run on a fake clock that never delivers another isolate's
/// answer: there the work runs inline.
final _testing = Platform.environment.containsKey('FLUTTER_TEST');
Future<R> _background<M, R>(ComputeCallback<M, R> callback, M message) =>
    _testing ? Future.value(callback(message)) : compute(callback, message);

// Isolate entry points are top-level functions with one message (a closure
// would also try to send whatever its scope holds, such as `ref`).
String _encodeSet((List<Map>, List<Map>) message) =>
    jsonEncode({'records': message.$1, 'categories': message.$2});
List<CatalogGroup> _groupMessage((CatalogSet, String, bool) message) =>
    groupCatalog(message.$1, message.$2, adult: message.$3);

CatalogSet _buildSet(List<Map> records, List<Map> categories) => CatalogSet(
  [
    for (final raw in records)
      if (raw['id'] is String)
        Entry(raw['id'] as String, Map<String, dynamic>.from(raw)),
  ],
  {
    for (final c in categories)
      if (c['id'] != null && c['name'] is String)
        '${c['id']}': c['name'] as String,
  },
);

/// One set of a source version, kept while the app runs (switching tabs
/// does not read it again; a new version is a new key) and on the device.
final catalogSetProvider =
    FutureProvider.family<CatalogSet, (String, String, String)>((
      ref,
      key,
    ) async {
      final (sourceId, version, group) = key;
      final (itemSet, categorySet) = _sets[group]!;
      final repository = ref.read(repositoryProvider);
      final uid = ref.read(accountProvider).asData?.value?.uid ?? '';
      final manifest = await repository.mutate('readCatalogManifest', {
        'id': sourceId,
        if (version.isNotEmpty) 'version': version,
      });
      final current = '${manifest['version'] ?? version}';
      final viewer = '${manifest['viewerKey'] ?? ''}';
      final dir = await _cacheDir();
      final prefix = _safe('${uid}_${sourceId}_$group');
      final file = dir == null
          ? null
          : File('${dir.path}/${prefix}_${_safe('${current}_$viewer')}.json');
      if (file != null && await file.exists()) {
        try {
          final body = await file.readAsString();
          return await _background(_decodeSet, body);
        } catch (_) {
          // Damaged copy: downloaded again below.
        }
      }

      int chunks(String set) =>
          (((manifest['sets'] as Map?)?[set] as Map?)?['chunks'] as num?)
              ?.toInt() ??
          0;
      Future<List<Map>> read(String set) async {
        final total = chunks(set);
        final pages = List<List<Map>>.filled(total, const []);
        var next = 0;
        Future<void> worker() async {
          while (next < total) {
            final n = next++;
            final page = await repository.mutate('readCatalogChunk', {
              'id': sourceId,
              'version': current,
              'set': set,
              'n': n,
            });
            pages[n] = (page['records'] as List? ?? const [])
                .whereType<Map>()
                .toList();
          }
        }

        await Future.wait([
          for (var i = 0; i < _parallelChunks && i < total; i++) worker(),
        ]);
        return [for (final page in pages) ...page];
      }

      final [records, categories] = await Future.wait([
        read(itemSet),
        read(categorySet),
      ]);
      if (file != null) {
        // Saved after the screen has it; older versions of this set go.
        unawaited(() async {
          try {
            final body = await _background(_encodeSet, (records, categories));
            await file.writeAsString(body, flush: true);
            await for (final old in dir!.list()) {
              final name = old.uri.pathSegments.last;
              if (old is File &&
                  name.startsWith('${prefix}_') &&
                  old.path != file.path) {
                await old.delete();
              }
            }
          } catch (_) {
            // Cache only.
          }
        }());
      }
      return _buildSet(records, categories);
    }, retry: (retryCount, error) => null);

/// One category of a catalog tab: the TV's name, its key and its titles
/// (A–Z).
@immutable
class CatalogGroup {
  const CatalogGroup(this.key, this.name, this.items);
  final String key, name;
  final List<Entry> items;
}

/// A–Z key: no accents, lower case, numbers with a fixed width ("Título 2" <
/// "Título 10"), as the TV sorts.
String _sortKey(String text) =>
    foldName(text)
        .replaceAllMapped(RegExp(r'\d+'), (m) => m[0]!.padLeft(10, '0'));

/// Categories of [kind] as the TV builds them (`catalogStore.categories` +
/// the menu order): the provider category name (by id, else the item's own)
/// through the TV's de-para; names that become the same text are one group.
/// Groups A–Z with the adult ones last; titles A–Z. [adult]: the "Adulto"
/// tab (adult items of [kind]); otherwise adult content never appears.
List<CatalogGroup> groupCatalog(
  CatalogSet set,
  String kind, {
  bool adult = false,
}) {
  final labels = <String, (String, String)>{};
  final groups = <String, (String, List<Entry>)>{};
  for (final item in set.items) {
    if (item.kind != kind || (!adult && isAdultEntry(item))) continue;
    final id = item.data['categoryId'];
    final raw =
        (id == null ? null : set.categoryNames['$id']) ??
        (item.text('category').isEmpty
            ? 'Sem categoria'
            : item.text('category'));
    final (key, name) = labels.putIfAbsent(raw, () {
      final name = categoryLabel(raw);
      return (categoryKey(name), name);
    });
    groups.putIfAbsent(key, () => (name, <Entry>[])).$2.add(item);
  }
  // Each title's key once (not on every comparison).
  final keys = <Entry, String>{
    for (final (_, items) in groups.values)
      for (final item in items) item: _sortKey(item.name),
  };
  final out = [
    for (final MapEntry(:key, value: (name, items)) in groups.entries)
      CatalogGroup(
        key,
        name,
        items..sort((a, b) => keys[a]!.compareTo(keys[b]!)),
      ),
  ];
  out.sort((a, b) {
    final adultFirst = (isAdultName(a.name) ? 1 : 0).compareTo(
      isAdultName(b.name) ? 1 : 0,
    );
    return adultFirst != 0
        ? adultFirst
        : _sortKey(a.name).compareTo(_sortKey(b.name));
  });
  return out;
}

/// Categories of one tab of a source (computed once per set and kind).
final catalogGroupsProvider =
    FutureProvider.family<
      List<CatalogGroup>,
      ({String sourceId, String version, String kind, bool adult})
    >((ref, key) async {
      final set = await ref.watch(
        catalogSetProvider((
          key.sourceId,
          key.version,
          key.adult ? 'adult' : key.kind,
        )).future,
      );
      // Off the interface thread: tens of thousands of titles.
      return _background(_groupMessage, (set, key.kind, key.adult));
    }, retry: (retryCount, error) => null);
