import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../domain/repository.dart';
import 'firebase_repository.dart';

final repositoryProvider = Provider<ManagerRepository>(
  (ref) => FirebaseManagerRepository(configured: false),
);
final authProvider = StreamProvider<String?>(
  (ref) => ref.watch(repositoryProvider).authChanges(),
  retry: (retryCount, error) => null,
);
// One initialization per authenticated UID, shared by routing and all screens.
// Login, session restoration and account retry follow the same lifecycle.
final accountProvider = StreamProvider<Account?>((ref) async* {
  final uid = ref.watch(authProvider.select((state) => state.asData?.value));
  if (uid == null) {
    yield null;
    return;
  }
  final repository = ref.watch(repositoryProvider);
  await repository.initializeAccount(uid).timeout(const Duration(seconds: 30));
  yield* repository.watchAccount(uid).map((account) {
    if (account == null || account.uid != uid) {
      throw const AppFailure('account-unavailable');
    }
    return account;
  });
}, retry: (retryCount, error) => null);
final familyProvider = StreamProvider<Family?>((ref) {
  final id = ref.watch(
    accountProvider.select((value) => value.asData?.value?.familyId),
  );
  return id == null
      ? Stream.value(null)
      : ref.watch(repositoryProvider).watchFamily(id);
}, retry: (retryCount, error) => null);
final adminProvider = Provider<bool>((ref) {
  final a = ref.watch(accountProvider).asData?.value,
      f = ref.watch(familyProvider).asData?.value;
  return a != null && f != null && f.isAdmin(a.uid);
});
// Permission belongs to the selected resource context, never to a global role.
final canManageResourcesProvider = Provider<bool>((ref) {
  final account = ref.watch(accountProvider).asData?.value;
  return account != null &&
      (account.familyId == null || ref.watch(adminProvider));
});
final canManageIptvProvider = Provider<bool>((ref) {
  final account = ref.watch(accountProvider).asData?.value;
  return account != null &&
      (account.iptvWorkspaceId != null ||
          account.familyId == null ||
          ref.watch(adminProvider));
});
final availableFamilyProvider = StreamProvider.autoDispose
    .family<Family?, String>(
      (ref, id) => ref.watch(repositoryProvider).watchFamily(id),
    );
final entriesProvider = StreamProvider.autoDispose.family<List<Entry>, String>((
  ref,
  collection,
) {
  final fid = ref.watch(
    accountProvider.select(
      (value) => collection == 'invitations'
          ? value.asData?.value?.uid
          : collection == 'members'
          ? value.asData?.value?.familyId
          : collection == 'sources'
          ? value.asData?.value?.iptvScopeId
          : value.asData?.value?.resourceScopeId,
    ),
  );
  return fid == null
      ? Stream.value([])
      : ref.watch(repositoryProvider).watchEntries(fid, collection);
}, retry: (retryCount, error) => null);

/// IPTV sources of the selected family: the spaces a family profile can be given.
final familySourcesProvider = StreamProvider.autoDispose<List<Entry>>((ref) {
  final fid = ref.watch(
    accountProvider.select((value) => value.asData?.value?.familyId),
  );
  return fid == null
      ? Stream.value(const [])
      : ref.watch(repositoryProvider).watchEntries(fid, 'sources');
}, retry: (retryCount, error) => null);
final entryProvider = StreamProvider.autoDispose
    .family<Entry?, ({String collection, String id})>((ref, key) {
      final fid = ref.watch(
        accountProvider.select(
          (value) => key.collection == 'members'
              ? value.asData?.value?.familyId
              : key.collection == 'sources'
              ? value.asData?.value?.iptvScopeId
              : value.asData?.value?.resourceScopeId,
        ),
      );
      return fid == null
          ? Stream.value(null)
          : ref
                .watch(repositoryProvider)
                .watchEntry(fid, key.collection, key.id);
    });
final clockProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

class UnlockedSourcesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(authProvider.select((s) => s.asData?.value));
    ref.watch(accountProvider.select((s) => s.asData?.value?.iptvScopeId));
    return <String>{};
  }

  void unlock(String sourceId) {
    state = {...state, sourceId};
    final timer = Timer(const Duration(minutes: 15), () => lock(sourceId));
    ref.onDispose(timer.cancel);
  }

  void lock(String sourceId) {
    state = state.where((id) => id != sourceId).toSet();
  }

  bool isUnlocked(String sourceId) => state.contains(sourceId);
}

final unlockedSourcesProvider =
    NotifierProvider<UnlockedSourcesNotifier, Set<String>>(
      UnlockedSourcesNotifier.new,
    );
