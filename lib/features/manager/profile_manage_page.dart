import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../../core/domain/public_identity.dart';

/// Família › Perfil › Gerenciar perfil. Every mutation goes through the backend;
/// the page only renders the profile document the listeners deliver.
class ProfileManagePage extends ConsumerWidget {
  const ProfileManagePage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l, key = (collection: 'profiles', id: id);
    return Scaffold(
      body: ref
          .watch(entryProvider(key))
          .when(
            loading: () => const AppLoadingSkeleton(),
            error: (e, s) =>
                ErrorState(onRetry: () => ref.invalidate(entryProvider(key))),
            data: (profile) => profile == null
                ? Center(child: Text(l.notFound))
                : _ProfileManageBody(profile: profile),
          ),
    );
  }
}

String profileTypeLabel(BuildContext context, String type) => switch (type) {
  'kids' => context.l.profileTypeKids,
  'admin' => context.l.profileTypeAdmin,
  'guest' => context.l.profileTypeGuest,
  _ => context.l.profileTypeRegular,
};

class _ProfileManageBody extends ConsumerStatefulWidget {
  const _ProfileManageBody({required this.profile});
  final Entry profile;
  @override
  ConsumerState<_ProfileManageBody> createState() => _ProfileManageBodyState();
}

class _ProfileManageBodyState extends ConsumerState<_ProfileManageBody> {
  bool busy = false;
  Entry get profile => widget.profile;
  String get type =>
      profile.text('type').isEmpty ? 'regular' : profile.text('type');
  String? get linkedUid => profile.data['linkedUid'] as String?;

  Future<void> _run(String action, Map<String, dynamic> payload) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).mutate(action, payload);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showLinkCode() async {
    setState(() => busy = true);
    try {
      final result = await ref.read(repositoryProvider).mutate(
        'createProfileLinkCode',
        {'profileId': profile.id},
      );
      if (!mounted) return;
      final code = result['code'] as String;
      await showAppModalSheet<void>(
        context: context,
        title: context.l.linkCodeTitle,
        description: context.l.linkCodeBody,
        content: Column(
          children: [
            AppSurface(
              child: Semantics(
                label: context.l.linkCodeTitle,
                child: QrImageView(
                  data: profileLinkQr(code),
                  backgroundColor: Colors.white,
                  size: 200,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.lg),
            SelectableText(
              code,
              key: const Key('profile-link-code'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          AppButton(
            label: context.l.close,
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      );
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _unlink() => confirmAndRun(
    context,
    title: context.l.unlinkAccountTitle,
    body: context.l.unlinkAccountBody(profile.name),
    confirmLabel: context.l.unlinkAccount,
    operation: () => ref.read(repositoryProvider).mutate(
      'unlinkProfileAccount',
      {'profileId': profile.id},
    ),
  );

  /// One confirmation per category; a fresh requestId per confirmed attempt
  /// lets the backend deduplicate repeated deliveries of the same request.
  Future<void> _clear(String category) async {
    final l = context.l, name = profile.name;
    final (title, body, confirm) = switch (category) {
      'favorites' => (
        l.clearFavoritesTitle,
        l.clearFavoritesBody(name),
        l.clearFavorites,
      ),
      'watched' => (
        l.clearWatchedTitle,
        l.clearWatchedBody(name),
        l.clearWatched,
      ),
      _ => (l.clearProgressTitle, l.clearProgressBody(name), l.clearProgress),
    };
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}${Random.secure().nextInt(1 << 32)}';
    final done = await confirmAndRun(
      context,
      title: title,
      body: body,
      confirmLabel: confirm,
      operation: () => ref.read(repositoryProvider).mutate('clearProfileData', {
        'profileId': profile.id,
        'category': category,
        'requestId': requestId,
      }),
    );
    if (done && mounted) {
      showAppFeedbackSheet(context: context, message: l.dataCleared);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final account = ref.watch(accountProvider).asData?.value;
    final admin = ref.watch(canManageResourcesProvider);
    final inFamily = account?.familyId != null;
    final linkable = admin && inFamily && (type == 'regular' || type == 'kids');
    return PageTemplate(
      title: profile.name,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l.profileInfo),
          AppSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l.profileType}: ${profileTypeLabel(context, type)}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (type != 'guest') ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    linkedUid == null ? l.accountNotLinked : l.accountLinked,
                    key: const Key('profile-link-status'),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                if (type == 'guest') ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l.guestHint,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (type == 'guest' && admin && inFamily)
            NeumorphicSwitchTile(
              key: const Key('guest-enabled'),
              title: l.guestEnabled,
              value: profile.data['enabled'] != false,
              disabled: busy,
              onChanged: (value) => _run('setGuestEnabled', {'enabled': value}),
            ),
          if (linkable && linkedUid == null)
            EntryTile(
              title: l.linkAccount,
              icon: AppIcons.link,
              onTap: busy ? null : _showLinkCode,
            ),
          if (linkable && linkedUid != null)
            EntryTile(
              title: l.unlinkAccount,
              icon: AppIcons.unlock,
              onTap: busy ? null : _unlink,
            ),
          if (admin && type != 'guest' && type != 'admin')
            EntryTile(
              title: l.edit,
              icon: AppIcons.edit,
              onTap: () => context.push(
                '/users/${profile.id}/edit',
                extra: profile.name,
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(l.permissionsTitle),
          if (type == 'admin')
            Text(
              l.adminFullAccess,
              style: const TextStyle(color: AppColors.textSecondary),
            )
          else
            _PermissionsSection(profile: profile, editable: admin),
          if (type != 'guest') ...[
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(l.manageData),
            EntryTile(
              title: l.favorites,
              icon: AppIcons.favorite,
              onTap: () => context.push('/users/${profile.id}/favorites'),
            ),
            EntryTile(
              title: l.continueWatching,
              icon: AppIcons.play,
              onTap: () => context.push('/users/${profile.id}/progress'),
            ),
            if (admin) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton.red(
                key: const Key('clear-favorites'),
                label: l.clearFavorites,
                icon: AppIcons.delete,
                onPressed: () => _clear('favorites'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton.red(
                key: const Key('clear-watched'),
                label: l.clearWatched,
                icon: AppIcons.delete,
                onPressed: () => _clear('watched'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton.red(
                key: const Key('clear-progress'),
                label: l.clearContinueWatching,
                icon: AppIcons.delete,
                onPressed: () => _clear('progress'),
              ),
            ],
          ],
          if (admin && type != 'admin') ...[
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              key: const Key('remove-profile'),
              label: l.remove,
              onPressed: () async {
                final removed = await confirmAndRun(
                  context,
                  title: l.confirmRemoval,
                  body: l.removalBody,
                  confirmLabel: l.remove,
                  operation: () => ref.read(repositoryProvider).mutate(
                    'deleteProfile',
                    {'id': profile.id},
                  ),
                );
                if (removed && context.mounted) context.pop();
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Spaces are IPTV source × content type, the structure the backend enforces.
class _PermissionsSection extends ConsumerStatefulWidget {
  const _PermissionsSection({required this.profile, required this.editable});
  final Entry profile;
  final bool editable;
  @override
  ConsumerState<_PermissionsSection> createState() =>
      _PermissionsSectionState();
}

class _PermissionsSectionState extends ConsumerState<_PermissionsSection> {
  bool busy = false;
  Map<String, dynamic> get permissions =>
      (widget.profile.data['permissions'] as Map?)?.cast<String, dynamic>() ??
      const {};
  bool get allSpaces => permissions['allSpaces'] != false;
  List<String> get spaces =>
      ((permissions['spaces'] as List?) ?? const []).cast<String>();

  Future<void> _save(bool all, List<String> next) async {
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).mutate('setProfilePermissions', {
        'profileId': widget.profile.id,
        'allSpaces': all,
        'spaces': next,
      });
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l, editable = widget.editable && !busy;
    final kinds = {
      'channel': l.spaceLive,
      'movie': l.spaceMovies,
      'series': l.spaceSeries,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.profile.text('type') == 'kids')
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              l.kidsRestrictionNote,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        NeumorphicSwitchTile(
          key: const Key('all-spaces'),
          title: l.allSpaces,
          subtitle: l.allSpacesHint,
          value: allSpaces,
          disabled: !editable,
          onChanged: (value) => _save(value, spaces),
        ),
        if (!allSpaces)
          ref
              .watch(familySourcesProvider)
              .when(
                loading: () => const AppLoadingSkeleton(),
                error: (e, s) => ErrorState(
                  onRetry: () => ref.invalidate(familySourcesProvider),
                ),
                data: (sources) => sources.isEmpty
                    ? Text(
                        l.noFamilySources,
                        style: const TextStyle(color: AppColors.textSecondary),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final source in sources) ...[
                            SectionHeader(source.name),
                            for (final kind in kinds.entries)
                              NeumorphicSwitchTile(
                                key: Key('space-${source.id}-${kind.key}'),
                                title: kind.value,
                                value: spaces.contains(
                                  '${source.id}:${kind.key}',
                                ),
                                disabled: !editable,
                                onChanged: (value) {
                                  final id = '${source.id}:${kind.key}';
                                  _save(
                                    false,
                                    value
                                        ? [...spaces, id]
                                        : spaces.where((s) => s != id).toList(),
                                  );
                                },
                              ),
                          ],
                        ],
                      ),
              ),
      ],
    );
  }
}
