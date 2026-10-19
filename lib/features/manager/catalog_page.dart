import 'dart:async';
import 'widgets/public_identity_sheet.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import 'widgets/entries_view.dart';
import 'widgets/home_welcome_state.dart';

class CatalogPageView extends ConsumerStatefulWidget {
  const CatalogPageView({super.key});
  @override
  ConsumerState<CatalogPageView> createState() => _CatalogPageViewState();
}

class _CatalogPageViewState extends ConsumerState<CatalogPageView> {
  final search = TextEditingController();
  Timer? debounce;
  String query = '';
  Entry? source;
  List<Entry> items = [];
  Object? cursor, error;
  bool loading = false, more = false;
  int generation = 0;
  String? activeScopeId, scheduledSourceKey;

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false, Entry? selected}) async {
    if (loading && !reset && selected == null) return;
    final next = selected ?? source;
    final fid = ref.read(accountProvider).asData?.value?.iptvScopeId;
    if (next == null || fid == null) return;
    final request = ++generation;
    setState(() {
      source = next;
      activeScopeId = fid;
      loading = true;
      error = null;
      if (reset) {
        items = [];
        cursor = null;
        more = false;
      }
    });
    try {
      final page = await ref
          .read(repositoryProvider)
          .catalog(fid, next, query, cursor: cursor)
          .timeout(const Duration(seconds: 30));
      if (!mounted ||
          request != generation ||
          ref.read(accountProvider).asData?.value?.iptvScopeId != fid) {
        return;
      }
      setState(() {
        items = {
          for (final item in [...items, ...page.items]) item.id: item,
        }.values.toList();
        cursor = page.cursor;
        more = page.hasMore;
      });
    } catch (failure) {
      if (mounted && request == generation) setState(() => error = failure);
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  void scheduleSource(Entry next, String scopeId) {
    final key = '$scopeId/${next.id}/${next.text('version')}';
    if (scheduledSourceKey == key) return;
    scheduledSourceKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          scheduledSourceKey == key &&
          ref.read(accountProvider).asData?.value?.iptvScopeId == scopeId) {
        load(reset: true, selected: next);
      }
    });
  }

  Future<void> favorite(Entry entry) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.lg),
          child: Consumer(
            builder: (c, modalRef, child) {
              final canCreate = modalRef.watch(canManageResourcesProvider);
              return EntriesView(
                collection: 'profiles',
                empty: EmptyState(
                  title: c.l.emptyUsers,
                  body: canCreate ? c.l.noProfilesBody : c.l.memberSetupHint,
                  icon: AppIcons.users,
                  action: canCreate
                      ? AppButton(
                          label: c.l.newProfile,
                          onPressed: () {
                            Navigator.pop(c);
                            context.push('/users/add');
                          },
                        )
                      : null,
                ),
                builder: (profiles) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.l.profiles),
                    ...profiles.map(
                      (profile) => EntryTile(
                        title: profile.name,
                        onTap: () => Navigator.pop(c, profile.id),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    if (id == null) return;
    try {
      await ref.read(repositoryProvider).mutate('favorite', {
        'profileId': id,
        'contentId': entry.id,
        'title': entry.name,
      });
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    ref.listen(
      accountProvider.select((value) => value.asData?.value?.iptvScopeId),
      (previous, next) {
        if (previous == next) return;
        debounce?.cancel();
        generation++;
        setState(() {
          source = null;
          activeScopeId = null;
          scheduledSourceKey = null;
          items = [];
          cursor = null;
          error = null;
          more = false;
          loading = false;
        });
      },
    );
    return PageTemplate(
      title: l.home,
      hasBottomNav: true,
      action: CircularButton(label: l.publicUserCode, icon: AppIcons.qr,
        size: AppDimensions.touch,
        onPressed: () => showPublicIdentity(context, ref.read(accountProvider).asData?.value?.publicCode)),
      child: ref
          .watch(accountProvider)
          .when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const AppLoadingSkeleton(),
            error: (e, stack) =>
                ErrorState(onRetry: () => ref.invalidate(accountProvider)),
            data: (account) {
              if (account?.iptvScopeId == null) return const HomeWelcomeState();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NeumorphicSearchField(
                    controller: search,
                    hintText: l.search,
                    onChanged: (value) {
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 350), () {
                        query = value;
                        load(reset: true);
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  EntriesView(
                    collection: 'sources',
                    empty: const HomeWelcomeState(),
                    builder: (sources) {
                      final unlocked = ref.watch(unlockedSourcesProvider);
                      final ready = sources
                          .where(
                            (entry) =>
                                entry.text('version').isNotEmpty &&
                                (entry.data['isProtected'] != true ||
                                    unlocked.contains(entry.id)),
                          )
                          .toList();
                      if (ready.isEmpty) {
                        final failed = sources.every(
                          (entry) => entry.text('status') == 'error',
                        );
                        return EmptyState(
                          title: failed ? l.catalogSyncFailed : l.sourceQueued,
                          body: failed ? l.sourceError : l.catalogPreparing,
                          action: Column(
                            children: [
                              AppButton(
                                label: l.iptv,
                                onPressed: () => context.go('/iptv'),
                              ),
                              const SizedBox(height: AppTokens.md),
                              AppButton(
                                label: l.retry,
                                onPressed: () =>
                                    ref.invalidate(entriesProvider('sources')),
                              ),
                            ],
                          ),
                        );
                      }
                      final matching = ready
                          .where((entry) => entry.id == source?.id)
                          .firstOrNull;
                      if (source == null ||
                          activeScopeId != account!.iptvScopeId ||
                          matching == null ||
                          matching.text('version') != source!.text('version')) {
                        scheduleSource(
                          matching ?? ready.first,
                          account!.iptvScopeId!,
                        );
                        return const AppLoadingSkeleton();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppDropdownField<String>(
                            key: ValueKey(source!.id),
                            initialValue: source!.id,
                            label: l.source,
                            items: ready
                                .map(
                                  (entry) => DropdownMenuItem(
                                    value: entry.id,
                                    child: Text(
                                      entry.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (id) => load(
                              reset: true,
                              selected: ready.firstWhere(
                                (entry) => entry.id == id,
                              ),
                            ),
                          ),
                          SectionHeader(l.catalog),
                          if (matching.text('status') == 'error')
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppTokens.md,
                              ),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  l.sourceError,
                                  style: const TextStyle(
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                            ),
                          if (error != null)
                            ErrorState(
                              onRetry: () => load(reset: items.isEmpty),
                            ),
                          if (loading && items.isEmpty)
                            const AppLoadingSkeleton()
                          else if (items.isEmpty && error == null)
                            query.trim().isEmpty
                                ? const HomeWelcomeState(catalogEmpty: true)
                                : EmptyState(
                                    title: l.noResults,
                                    body: l.noResultsBody,
                                    icon: AppIcons.search,
                                    action: AppButton(
                                      label: l.clearSearch,
                                      onPressed: () {
                                        search.clear();
                                        query = '';
                                        load(reset: true);
                                      },
                                    ),
                                  ),
                          ...items.map(
                            (entry) => EntryTile(
                              title: entry.name,
                              subtitle: entry.text('category'),
                              icon: AppIcons.iptv,
                              onTap: () => showModalBottomSheet<void>(
                                context: context,
                                useRootNavigator: true,
                                builder: (c) => SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.all(AppTokens.lg),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          entry.name,
                                          style: Theme.of(c)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                        const SizedBox(height: AppTokens.lg),
                                        AppButton(
                                          label: l.favorite,
                                          icon: AppIcons.favorite,
                                          onPressed: () {
                                            Navigator.pop(c);
                                            favorite(entry);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (loading && items.isNotEmpty)
                            const AppLoadingSkeleton(rows: 1)
                          else if (more && error == null)
                            AppButton(label: l.more, onPressed: load),
                          const SizedBox(height: AppTokens.xl),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
    );
  }
}
