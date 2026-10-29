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
            const SizedBox(height: AppSpacing.lg),
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
          // Header: avatar, name and role.
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
          if (type == 'guest') ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l.guestHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (lastActive > 0)
            EntryTile(
              key: const Key('member-last-sync'),
              title: l.lastSyncTitle,
              subtitle: formatCardDateTime(
                context,
                DateTime.fromMillisecondsSinceEpoch(lastActive),
              ),
              icon: AppIcons.refresh,
            ),

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

          // Lists: Continuar assistindo, Favoritos, Lista de desejos, Assistidos.
          if (showContent) _LibraryCards(profileId: profile.id),

          // Personal PIN: one card, only on the account's own profile.
          if (own && type != 'guest') _PinCard(profile: profile),

          // Content: kids classification and the allowed types.
          SectionHeader(l.contentSection),
          if (type == 'regular' || type == 'kids')
            NeumorphicSwitchTile(
              key: const Key('kids-account-toggle'),
              title: l.kidsAccount,
              subtitle: type == 'kids' ? l.kidsRestrictionNote : null,
              value: type == 'kids',
              disabled: busy || !linkable,
              onChanged: (value) => _run('saveProfile', {
                'id': profile.id,
                'name': profile.name,
                'type': value ? 'kids' : 'regular',
              }),
            ),
          _ContentToggles(profile: profile, admin: admin, own: own),

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

/// One card per list with its name and how many titles it holds; tapping
/// opens the list.
class _LibraryCards extends ConsumerWidget {
  const _LibraryCards({required this.profileId});
  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(profileLibraryProvider(profileId)).asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (kind, icon) in [
          (LibraryKind.continueWatching, AppIcons.play),
          (LibraryKind.favorites, AppIcons.favorite),
          (LibraryKind.wishlist, AppIcons.add),
          (LibraryKind.watched, AppIcons.check),
        ])
          EntryTile(
            key: ValueKey('library-${kind.name}'),
            title: libraryTitle(context, kind),
            icon: icon,
            trailing: library == null
                ? null
                : Text(
                    '${library.of(kind).length}',
                    key: ValueKey('library-${kind.name}-count'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
            onTap: () => context.push('/users/$profileId/library/${kind.name}'),
          ),
      ],
    );
  }
}

/// Canais, Filmes, Séries and Adulto. The administrator sets what each
/// profile may see; a member narrows Canais/Filmes/Séries on its own profile
/// only, within those limits. Adult content is the administrator's alone, and
/// kids profiles never get it. Anyone else only sees the current state.
class _ContentToggles extends ConsumerStatefulWidget {
  const _ContentToggles({
    required this.profile,
    required this.admin,
    required this.own,
  });
  final Entry profile;
  final bool admin, own;
  @override
  ConsumerState<_ContentToggles> createState() => _ContentTogglesState();
}

class _ContentTogglesState extends ConsumerState<_ContentToggles> {
  static const all = ['channel', 'movie', 'series'];
  bool busy = false;

  Map<String, dynamic> _map(String key) =>
      (widget.profile.data[key] as Map?)?.cast<String, dynamic>() ?? const {};
  String get type => widget.profile.text('type').isEmpty
      ? 'regular'
      : widget.profile.text('type');
  List<String>? _kinds(Map<String, dynamic> m) =>
      (m['kinds'] as List?)?.whereType<String>().toList();

  /// Types the administrator allows (its own profile is never limited).
  List<String> get limitKinds =>
      type == 'admin' ? all : _kinds(_map('permissions')) ?? all;

  /// The member's own narrowing (null: none).
  List<String>? get prefKinds => _kinds(_map('preferences'));
  bool get limitAdult =>
      type != 'kids' && _map('permissions')['adult'] != false;
  bool get prefAdult => _map('preferences')['adult'] != false;

  /// The administrator edits the limits of other profiles; the account linked
  /// to the profile (the administrator included) edits its own preferences.
  bool get editsPreferences => widget.own;
  bool get editsLimits => widget.admin && !widget.own;

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

  void _toggleKind(String kind, bool value) {
    if (editsPreferences) {
      final current = prefKinds ?? limitKinds;
      final next = value
          ? {...current, kind}.toList()
          : current.where((k) => k != kind).toList();
      // Everything allowed again: no own restriction.
      final none = limitKinds.every(next.contains);
      _mutate('setProfilePreferences', {
        'kinds': none
            ? null
            : [
                for (final k in all)
                  if (next.contains(k)) k,
              ],
      });
    } else {
      final next = value
          ? {...limitKinds, kind}.toList()
          : limitKinds.where((k) => k != kind).toList();
      _mutate('setProfilePermissions', {
        'profileId': widget.profile.id,
        'kinds': [
          for (final k in all)
            if (next.contains(k)) k,
        ],
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final labels = {
      'channel': l.contentChannels,
      'movie': l.spaceMovies,
      'series': l.spaceSeries,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final kind in all)
          NeumorphicSwitchTile(
            key: Key('content-$kind'),
            title: labels[kind]!,
            subtitle: editsPreferences && !limitKinds.contains(kind)
                ? l.notAllowedByAdmin
                : null,
            value:
                limitKinds.contains(kind) &&
                (prefKinds?.contains(kind) ?? true),
            disabled:
                busy ||
                !(editsLimits ||
                    (editsPreferences && limitKinds.contains(kind))),
            onChanged: (value) => _toggleKind(kind, value),
          ),
        // Kids profiles never see adult content (system rule): no toggle.
        if (type != 'kids')
          NeumorphicSwitchTile(
            key: const Key('content-adult'),
            title: l.adultContent,
            subtitle: l.adultContentHint,
            value: limitAdult && prefAdult,
            disabled: busy || !widget.admin,
            onChanged: (value) => _mutate('setProfilePermissions', {
              'profileId': widget.profile.id,
              'adult': value,
            }),
          ),
      ],
    );
  }
}

/// Personal PIN of the account's own profile: one card; tapping opens the
/// sheet to set it or, when on, to change or turn it off. The administrator
/// never sees nor sets another member's PIN (backend rule).
class _PinCard extends StatelessWidget {
  const _PinCard({required this.profile});
  final Entry profile;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final on = (profile.data['personalPin'] as Map?)?['configured'] == true;
    void form({required bool remove}) => showAppModalSheet<void>(
      context: context,
      builder: (_) => _PersonalPinForm(configured: on, remove: remove),
    );
    return EntryTile(
      key: const Key('personal-pin'),
      title: l.personalPin,
      subtitle: on ? l.personalPinOn : l.personalPinOff,
      icon: on ? AppIcons.lock : AppIcons.unlock,
      onTap: () async {
        if (!on) return form(remove: false);
        final remove = await showAppModalSheet<bool>(
          context: context,
          builder: (sheet) => AppModalSheet(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(icon: AppIcons.lock, title: l.personalPin),
                SheetActionRow(
                  key: const Key('personal-pin-change'),
                  icon: AppIcons.edit,
                  label: l.changePersonalPin,
                  onTap: () => Navigator.of(sheet).pop(false),
                ),
                SheetActionRow(
                  key: const Key('personal-pin-remove'),
                  icon: AppIcons.unlock,
                  label: l.disablePersonalPin,
                  onTap: () => Navigator.of(sheet).pop(true),
                ),
              ],
            ),
          ),
        );
        if (remove != null && context.mounted) form(remove: remove);
      },
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
