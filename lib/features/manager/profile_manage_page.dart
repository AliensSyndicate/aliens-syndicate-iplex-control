import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../../core/domain/public_identity.dart';
import 'widgets/profile_library.dart';

/// Família › integrante: header (avatar, name, role, account, last sync),
/// permissions, the member's own preferences and PIN, content (Continuar
/// assistindo, Favoritos, Lista de desejos, Assistidos) and account actions.
/// Every mutation goes through the backend, which enforces who may do what.
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
                : _MemberDetails(profile: profile),
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

/// Short role of a family card: Admin, Infantil, Membro or Visitante.
String roleLabel(BuildContext context, String type) => switch (type) {
  'admin' => context.l.roleAdmin,
  'kids' => context.l.roleKids,
  'guest' => context.l.roleGuest,
  _ => context.l.roleMember,
};

/// Discreet role mark (pill on the elevated surface).
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm + 2,
      vertical: AppSpacing.xxs + 1,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadii.full),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

class _MemberDetails extends ConsumerStatefulWidget {
  const _MemberDetails({required this.profile});
  final Entry profile;
  @override
  ConsumerState<_MemberDetails> createState() => _MemberDetailsState();
}

class _MemberDetailsState extends ConsumerState<_MemberDetails> {
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

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final account = ref.watch(accountProvider).asData?.value;
    final admin = ref.watch(canManageResourcesProvider);
    final inFamily = account?.familyId != null;
    final own = linkedUid != null && linkedUid == account?.uid;
    final members =
        ref.watch(entriesProvider('members')).asData?.value ?? const [];
    final linked = members.where((m) => m.id == linkedUid).firstOrNull;
    final lastActive = linked?.number('lastActiveAt') ?? 0;
    final linkable = admin && inFamily && (type == 'regular' || type == 'kids');
    // Personal data: the administrator or the account linked to the profile.
    final showContent = type != 'guest' && (admin || own);

    return PageTemplate(
      title: '',
      showBack: true,
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        key: const Key('member-details'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: EdgeToEdge.padded([
          // Header: avatar, name, role, account and last sync.
          Center(
            child: AppAvatar(
              key: const Key('member-avatar'),
              name: profile.name,
              photoUrl: linked?.text('photoUrl'),
              size: 96,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            profile.name,
            key: const Key('member-name'),
            textAlign: TextAlign.center,
            style: AppTypography.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(child: RoleChip(label: roleLabel(context, type))),
          const SizedBox(height: AppSpacing.sm),
          if (type == 'guest')
            Text(
              l.guestHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            )
          else
            Text(
              linkedUid == null ? l.accountNotLinked : l.accountLinked,
              key: const Key('profile-link-status'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          if (lastActive > 0) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l.lastSyncLabel(
                formatCardDateTime(
                  context,
                  DateTime.fromMillisecondsSinceEpoch(lastActive),
                ),
              ),
              key: const Key('member-last-sync'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          if (type == 'guest' && admin && inFamily)
            NeumorphicSwitchTile(
              key: const Key('guest-enabled'),
              title: l.guestAccount,
              subtitle: l.guestAccountHint,
              value: profile.data['enabled'] != false,
              disabled: busy,
              onChanged: (value) => _run('setGuestEnabled', {
                'enabled': value,
                'name': l.profileTypeGuest,
              }),
            ),

          if (linkable)
            NeumorphicSwitchTile(
              key: const Key('kids-account-toggle'),
              title: l.kidsAccount,
              value: type == 'kids',
              disabled: busy,
              onChanged: (value) => _run('saveProfile', {
                'id': profile.id,
                'name': profile.name,
                'type': value ? 'kids' : 'regular',
              }),
            ),

          // Administrator limits.
          if (type == 'admin')
            Text(
              l.adminFullAccess,
              style: const TextStyle(color: AppColors.textSecondary),
            )
          else if (admin) ...[
            SectionHeader(l.adminLimitsTitle),
            Text(
              l.adminLimitsHint,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            _AccessEditor(profile: profile, mode: _AccessMode.limits),
          ],

          // The member's own preferences, within the limits.
          if (own && type != 'admin' && type != 'guest') ...[
            SectionHeader(l.myPreferences),
            Text(
              l.myPreferencesHint,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            _AccessEditor(profile: profile, mode: _AccessMode.preferences),
          ],

          // Security: the personal PIN (own profile only) and, for the
          // administrator, the family's parental control.
          if (own && type != 'guest') ...[
            SectionHeader(l.securitySection),
            _PersonalPin(profile: profile),
            if (type == 'admin')
              EntryTile(
                key: const Key('parental-control'),
                title: l.parentalControl,
                icon: AppIcons.lock,
                onTap: () => context.push('/users/parental'),
              ),
          ],

          if (showContent) _Content(profile: profile, canClear: admin),

          // Account actions.
          if (admin && type != 'admin' && type != 'guest') ...[
            SectionHeader(l.accountSection),
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
                onTap: busy
                    ? null
                    : () => confirmAndRun(
                        context,
                        title: l.unlinkAccountTitle,
                        body: l.unlinkAccountBody(profile.name),
                        confirmLabel: l.unlinkAccount,
                        operation: () => ref.read(repositoryProvider).mutate(
                          'unlinkProfileAccount',
                          {'profileId': profile.id},
                        ),
                      ),
              ),
            EntryTile(
              title: l.edit,
              icon: AppIcons.edit,
              onTap: () => context.push(
                '/users/${profile.id}/edit',
                extra: profile.name,
              ),
            ),
            if (linkedUid != null)
              EntryTile(
                key: const Key('remove-from-family'),
                title: l.removeFromFamily,
                icon: AppIcons.users,
                onTap: () => confirmAndRun(
                  context,
                  title: l.removeFromFamily,
                  body: l.removeFromFamilyBody(profile.name),
                  confirmLabel: l.removeFromFamily,
                  operation: () => ref.read(repositoryProvider).mutate(
                    'removeMember',
                    {'id': linkedUid},
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            AppButton.red(
              key: const Key('remove-profile'),
              label: l.deleteProfile,
              onPressed: () async {
                final removed = await confirmAndRun(
                  context,
                  title: l.confirmRemoval,
                  body: l.removalBody,
                  confirmLabel: l.deleteProfile,
                  operation: () => ref.read(repositoryProvider).mutate(
                    'deleteProfile',
                    {'id': profile.id},
                  ),
                );
                if (removed && context.mounted) context.pop();
              },
            ),
          ],
          if (own && !admin) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: const Key('leave-family'),
              label: l.leaveFamily,
              onPressed: () async {
                final done = await confirmAndRun(
                  context,
                  title: l.leaveFamily,
                  body: l.leaveFamilyBody,
                  confirmLabel: l.leaveFamily,
                  operation: () =>
                      ref.read(repositoryProvider).mutate('leaveFamily'),
                );
                if (done && context.mounted) context.pop();
              },
            ),
          ],
        ]),
      ),
    );
  }
}

/// Content sections of the profile (shared [LibrarySection] layout).
class _Content extends ConsumerWidget {
  const _Content({required this.profile, required this.canClear});
  final Entry profile;
  final bool canClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(profileLibraryProvider(profile.id));
    return EdgeToEdge(
      child: data.when(
        loading: () => const Padding(
          padding: EdgeToEdge.inset,
          child: AppLoadingSkeleton(rows: 3),
        ),
        error: (e, s) => Padding(
          padding: EdgeToEdge.inset,
          child: ErrorState(
            onRetry: () => ref.invalidate(profileLibraryProvider(profile.id)),
          ),
        ),
        data: (library) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (kind, items) in [
              (LibraryKind.continueWatching, library.continueWatching),
              (LibraryKind.favorites, library.favorites),
              (LibraryKind.wishlist, library.wishlist),
              (LibraryKind.watched, library.watched),
            ])
              LibrarySection(
                kind: kind,
                profileId: profile.id,
                profileName: profile.name,
                items: items,
                canClear: canClear,
              ),
          ],
        ),
      ),
    );
  }
}

enum _AccessMode { limits, preferences }

/// Adult content and sections (IPTV source × content type). In [limits] mode
/// the administrator sets the maximum; in [preferences] mode the member
/// narrows its own access, only inside those limits.
class _AccessEditor extends ConsumerStatefulWidget {
  const _AccessEditor({required this.profile, required this.mode});
  final Entry profile;
  final _AccessMode mode;
  @override
  ConsumerState<_AccessEditor> createState() => _AccessEditorState();
}

class _AccessEditorState extends ConsumerState<_AccessEditor> {
  bool busy = false;
  Map<String, dynamic> get limits =>
      (widget.profile.data['permissions'] as Map?)?.cast<String, dynamic>() ??
      const {};
  Map<String, dynamic> get prefs =>
      (widget.profile.data['preferences'] as Map?)?.cast<String, dynamic>() ??
      const {};
  bool get limitsAll => limits['allSpaces'] != false;
  List<String> get limitSpaces =>
      ((limits['spaces'] as List?) ?? const []).cast<String>();
  bool get limitAdult => limits['adult'] != false;
  bool get prefAdult => prefs['adult'] != false;
  List<String>? get prefSpaces => (prefs['spaces'] as List?)?.cast<String>();
  bool get kids => widget.profile.text('type') == 'kids';
  bool get preferences => widget.mode == _AccessMode.preferences;

  Future<void> _mutate(String action, Map<String, dynamic> payload) async {
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).mutate(action, payload);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveLimits({bool? all, List<String>? spaces, bool? adult}) =>
      _mutate('setProfilePermissions', {
        'profileId': widget.profile.id,
        'allSpaces': all ?? limitsAll,
        'spaces': spaces ?? limitSpaces,
        'adult': adult ?? limitAdult,
      });

  Future<void> _savePrefs({
    bool? adult,
    List<String>? spaces,
    bool keep = true,
  }) => _mutate('setProfilePreferences', {
    'adult': adult ?? prefAdult,
    'spaces': keep ? (spaces ?? prefSpaces) : spaces,
  });

  bool allowed(String space) => limitsAll || limitSpaces.contains(space);

  @override
  Widget build(BuildContext context) {
    final l = context.l, enabled = !busy;
    final kinds = {
      'channel': l.spaceLive,
      'movie': l.spaceMovies,
      'series': l.spaceSeries,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kids)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              l.kidsRestrictionNote,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          NeumorphicSwitchTile(
            key: Key('${widget.mode.name}-adult'),
            title: l.adultContent,
            subtitle: preferences && !limitAdult
                ? l.notAllowedByAdmin
                : l.adultContentHint,
            value: preferences ? limitAdult && prefAdult : limitAdult,
            disabled: !enabled || (preferences && !limitAdult),
            onChanged: (value) => preferences
                ? _savePrefs(adult: value)
                : _saveLimits(adult: value),
          ),
        if (!preferences)
          NeumorphicSwitchTile(
            key: const Key('all-spaces'),
            title: l.allSpaces,
            subtitle: l.allSpacesHint,
            value: limitsAll,
            disabled: !enabled,
            onChanged: (value) => _saveLimits(all: value),
          ),
        if (preferences || !limitsAll)
          ref
              .watch(familySourcesProvider)
              .when(
                loading: () => const AppLoadingSkeleton(),
                error: (e, s) => ErrorState(
                  onRetry: () => ref.invalidate(familySourcesProvider),
                ),
                data: (sources) {
                  final rows = [
                    for (final source in sources)
                      for (final kind in kinds.entries)
                        if (!preferences || allowed('${source.id}:${kind.key}'))
                          (source, kind),
                  ];
                  if (rows.isEmpty) {
                    return Text(
                      l.noFamilySources,
                      style: const TextStyle(color: AppColors.textSecondary),
                    );
                  }
                  final allowedIds = [
                    for (final (s, k) in rows) '${s.id}:${k.key}',
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (source, kind) in rows)
                        NeumorphicSwitchTile(
                          key: Key(
                            '${preferences ? 'pref' : 'space'}-${source.id}-${kind.key}',
                          ),
                          title: kind.value,
                          subtitle: source.name,
                          value: preferences
                              ? (prefSpaces?.contains(
                                      '${source.id}:${kind.key}',
                                    ) ??
                                    true)
                              : limitSpaces.contains(
                                  '${source.id}:${kind.key}',
                                ),
                          disabled: !enabled,
                          onChanged: (value) {
                            final id = '${source.id}:${kind.key}';
                            if (preferences) {
                              final current = prefSpaces ?? allowedIds;
                              final next = value
                                  ? [...current, id]
                                  : current.where((s) => s != id).toList();
                              // Everything allowed again: no own restriction.
                              final all = allowedIds.every(next.contains);
                              _savePrefs(
                                spaces: all ? null : next,
                                keep: false,
                              );
                            } else {
                              _saveLimits(
                                all: false,
                                spaces: value
                                    ? [...limitSpaces, id]
                                    : limitSpaces
                                          .where((s) => s != id)
                                          .toList(),
                              );
                            }
                          },
                        ),
                    ],
                  );
                },
              ),
      ],
    );
  }
}

/// Personal PIN of the account's own profile: on/off, set, change, turn off.
/// The administrator never sees nor sets another member's PIN (backend rule).
class _PersonalPin extends ConsumerWidget {
  const _PersonalPin({required this.profile});
  final Entry profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final on = (profile.data['personalPin'] as Map?)?['configured'] == true;
    void open({required bool remove}) => showAppModalSheet<void>(
      context: context,
      builder: (_) => _PersonalPinForm(configured: on, remove: remove),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EntryTile(
          key: const Key('personal-pin'),
          title: l.personalPin,
          subtitle: on ? l.personalPinOn : l.personalPinOff,
          lines: [l.personalPinHint],
          icon: on ? AppIcons.lock : AppIcons.unlock,
        ),
        AppButton(
          key: const Key('personal-pin-set'),
          label: on ? l.changePersonalPin : l.enablePersonalPin,
          onPressed: () => open(remove: false),
        ),
        if (on) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const Key('personal-pin-remove'),
            label: l.disablePersonalPin,
            onPressed: () => open(remove: true),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _PersonalPinForm extends ConsumerStatefulWidget {
  const _PersonalPinForm({required this.configured, required this.remove});
  final bool configured, remove;
  @override
  ConsumerState<_PersonalPinForm> createState() => _PersonalPinFormState();
}

class _PersonalPinFormState extends ConsumerState<_PersonalPinForm> {
  final formKey = GlobalKey<FormState>();
  final current = TextEditingController(),
      pin = TextEditingController(),
      confirm = TextEditingController();
  bool busy = false;
  Object? error;

  @override
  void dispose() {
    current.dispose();
    pin.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !formKey.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(repositoryProvider).mutate(
        widget.remove ? 'clearPersonalPin' : 'setPersonalPin',
        {
          if (widget.configured) 'currentPin': current.text.trim(),
          if (!widget.remove) ...{
            'pin': pin.text.trim(),
            'confirmPin': confirm.text.trim(),
          },
        },
      );
      if (!mounted) return;
      final message = widget.remove
          ? context.l.personalPinRemoved
          : context.l.personalPinSaved;
      final navigator = Navigator.of(context);
      navigator.pop();
      showAppFeedbackSheet(context: navigator.context, message: message);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    String? validate(String? v) {
      final value = v?.trim() ?? '';
      if (value.isEmpty) return l.requiredField;
      if (!RegExp(r'^\d{4}$').hasMatch(value)) return l.parentalPinLength;
      return null;
    }

    return AppModalSheet(
      title: widget.remove
          ? l.disablePersonalPin
          : widget.configured
          ? l.changePersonalPin
          : l.enablePersonalPin,
      description: l.personalPinHint,
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.configured) ...[
              AppTextField(
                key: const Key('personal-pin-current'),
                label: l.currentPinLabel,
                controller: current,
                secret: true,
                keyboardType: TextInputType.number,
                validator: validate,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (!widget.remove) ...[
              AppTextField(
                key: const Key('personal-pin-new'),
                label: l.newPinLabel,
                controller: pin,
                secret: true,
                keyboardType: TextInputType.number,
                validator: validate,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                key: const Key('personal-pin-confirm'),
                label: l.confirmPin,
                controller: confirm,
                secret: true,
                keyboardType: TextInputType.number,
                validator: (v) =>
                    validate(v) ??
                    (v?.trim() != pin.text.trim() ? l.pinMustMatch : null),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                failureText(context, error!),
                style: const TextStyle(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton.primary(
          key: const Key('personal-pin-save'),
          label: widget.remove ? l.disablePersonalPin : l.save,
          busy: busy,
          onPressed: submit,
        ),
        AppButton(
          label: l.cancel,
          onPressed: busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
