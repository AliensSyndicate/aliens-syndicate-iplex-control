import 'package:flutter/foundation.dart';
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

/// One set of a source version, kept while the app runs (switching tabs
/// does not read it again; a new version is a new key).
final catalogSetProvider =
    FutureProvider.family<CatalogSet, (String, String, String)>((
      ref,
      key,
    ) async {
      final (sourceId, version, group) = key;
      final (itemSet, categorySet) = _sets[group]!;
      final repository = ref.read(repositoryProvider);
      final manifest = await repository.mutate('readCatalogManifest', {
        'id': sourceId,
        if (version.isNotEmpty) 'version': version,
      });
      final current = '${manifest['version'] ?? version}';
      int chunks(String set) =>
          ((manifest['sets'] as Map?)?[set] as Map?)?['chunks'] is num
          ? (((manifest['sets'] as Map)[set] as Map)['chunks'] as num).toInt()
          : 0;
      Future<List<Map>> read(String set) async {
        final rows = <Map>[];
        // A few chunks at a time, in order.
        final total = chunks(set);
        for (var n = 0; n < total; n += 4) {
          final pages = await Future.wait([
            for (var i = n; i < n + 4 && i < total; i++)
              repository.mutate('readCatalogChunk', {
                'id': sourceId,
                'version': current,
                'set': set,
                'n': i,
              }),
          ]);
          for (final page in pages) {
            rows.addAll(
              (page['records'] as List? ?? const []).whereType<Map>(),
            );
          }
        }
        return rows;
      }

      final [records, categories] = await Future.wait([
        read(itemSet),
        read(categorySet),
      ]);
      return CatalogSet(
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
  final out = [
    for (final MapEntry(:key, value: (name, items)) in groups.entries)
      CatalogGroup(
        key,
        name,
        items..sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name))),
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
      return groupCatalog(set, key.kind, adult: key.adult);
    }, retry: (retryCount, error) => null);
