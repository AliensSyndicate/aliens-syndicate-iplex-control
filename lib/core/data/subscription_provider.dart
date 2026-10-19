import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import 'providers.dart';

/// Optional private billing data. It never gates Manager routes or operations.
/// Losing the administrator role also discards the previous subscription data.
final subscriptionProvider = StreamProvider.autoDispose<Entry?>((ref) {
  final familyId = ref.watch(
    accountProvider.select((account) => account.asData?.value?.resourceScopeId),
  );
  if (familyId == null || !ref.watch(canManageResourcesProvider)) return Stream.value(null);
  return ref
      .watch(repositoryProvider)
      .watchEntry(familyId, 'private', 'subscription');
}, retry: (retryCount, error) => null);
