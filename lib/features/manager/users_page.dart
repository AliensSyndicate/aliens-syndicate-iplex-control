import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/components.dart';
import '../../core/data/providers.dart';
import '../../core/domain/models.dart';
import 'profile_manage_page.dart';
import 'widgets/entries_view.dart';

/// Família: only the people of the family. Administrator first, members in
/// alphabetical order, then pending invitations and the guest last (when on).
/// Each card: avatar, name and role (Admin, Infantil, Membro, Visitante).
/// The administrator adds members ("+") and turns the guest account on/off;
/// everything else lives in the member's details page.
class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final account = ref.watch(accountProvider).asData?.value;
    final hasFamily = account?.familyId != null;
    final admin = ref.watch(adminProvider);
    final profiles = ref.watch(entriesProvider('profiles')).asData?.value;
    final guest = profiles?.where((p) => p.id == 'guest').firstOrNull;
    final guestOn = guest != null && guest.data['enabled'] != false;
    // A member account that is not linked to any profile yet (legacy).
    final unlinked =
        !admin &&
        hasFamily &&
        profiles != null &&
        !profiles.any((p) => p.data['linkedUid'] == account?.uid);
    return PageTemplate(
      title: l.familyTitle,
      hasBottomNav: true,
      action: admin
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasFamily) ...[
                  // Conta visitante: toggle icon (right = on, left = off). Off keeps
                  // the guest profile and its configuration.
                  Semantics(
                    toggled: guestOn,
                    child: CircularButton(
                      key: const Key('guest-toggle'),
                      label: l.guestAccount,
                      icon: guestOn ? AppIcons.toggleOn : AppIcons.toggleOff,
                      size: AppDimensions.touch,
                      onPressed: profiles == null
                          ? null
                          : () async {
                              try {
                                await ref.read(repositoryProvider).mutate(
                                  'setGuestEnabled',
                                  {
                                    'enabled': !guestOn,
                                    'name': l.profileTypeGuest,
                                  },
                                );
                              } catch (e) {
                                if (context.mounted) showFailure(context, e);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                CircularButton(
                  key: const Key('add-member-button'),
                  label: l.addMember,
                  icon: AppIcons.add,
                  size: AppDimensions.touch,
                  onPressed: () => context.push('/users/invite'),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ReceivedInvitations(),
          const _FamilyMembers(),
          if (unlinked)
            EntryTile(
              key: const Key('link-to-profile'),
              title: l.linkToProfile,
              icon: AppIcons.link,
              onTap: () => context.push('/family/link-profile'),
            ),
        ],
      ),
    );
  }
}

/// Invitations addressed to this account (the person decides; nothing is automatic).
class _ReceivedInvitations extends StatelessWidget {
  const _ReceivedInvitations();
  @override
  Widget build(BuildContext context) => EntriesView(
    collection: 'invitations',
    empty: const SizedBox.shrink(),
    builder: (items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(context.l.membershipRequests),
        ...items.map(
          (request) => EntryTile(
            title: request.text('familyName'),
            subtitle: context.l.invitePending,
            icon: AppIcons.users,
            onTap: () => showAppModalSheet<void>(
              context: context,
              title: request.text('familyName'),
              description: context.l.membershipAcceptHelp,
              builder: (c) => _MembershipResponse(
                id: request.id,
                name: request.text('familyName'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Alphabetical, accent and case insensitive.
String _sortKey(String name) => name
    .toLowerCase()
    .replaceAll(RegExp('[áàâãä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôõö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ç', 'c');

/// The family list: profiles (the family's people) with the photo of the
/// account linked to each, in the mandatory order.
class _FamilyMembers extends ConsumerWidget {
  const _FamilyMembers();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final account = ref.watch(accountProvider).asData?.value;
    final admin = ref.watch(adminProvider);
    if (account?.familyId == null) return const AppLoadingSkeleton();
    final members = ref.watch(entriesProvider('members'));
    final profiles = ref.watch(entriesProvider('profiles'));
    final sent = admin ? ref.watch(entriesProvider('sentInvitations')) : null;
    if (members.hasError || profiles.hasError) {
      return ErrorState(
        onRetry: () => ref
          ..invalidate(entriesProvider('members'))
          ..invalidate(entriesProvider('profiles')),
      );
    }
    final accounts = members.asData?.value, people = profiles.asData?.value;
    if (members.isLoading || accounts == null || people == null) {
      return const AppLoadingSkeleton();
    }
    final byUid = {for (final m in accounts) m.id: m};
    final live = people.where((p) => p.data['deleting'] != true).toList();
    final adminProfile = live.where((p) => p.text('type') == 'admin');
    final associates = live.where(
      (p) => p.text('type') != 'admin' && p.text('type') != 'guest',
    );
    final linkedUids = {for (final p in live) p.data['linkedUid']};
    // Accounts of the family without a profile (legacy): still listed.
    final orphans = accounts.where(
      (m) => m.text('role') != 'admin' && !linkedUids.contains(m.id),
    );
    final guest = live
        .where((p) => p.id == 'guest' && p.data['enabled'] != false)
        .firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;
    final pending =
        sent?.asData?.value.where((r) => r.number('expiresAt') > now) ??
        const <Entry>[];

    Widget card(Entry profile) {
      final type = profile.text('type').isEmpty
          ? 'regular'
          : profile.text('type');
      final linked = byUid[profile.data['linkedUid']];
      return EntryTile(
        key: ValueKey('profile-${profile.id}'),
        leading: AppAvatar(
          name: profile.name,
          photoUrl: linked?.text('photoUrl'),
          size: AppDimensions.touch,
        ),
        title: profile.name,
        subtitle: roleLabel(context, type),
        // Everyone opens any card; only the administrator (and the member on
        // its own profile) can change something there.
        onTap: () => context.push('/users/${profile.id}'),
      );
    }

    final sorted = [
      for (final p in associates) (_sortKey(p.name), card(p)),
      for (final m in orphans)
        (
          _sortKey(m.name),
          EntryTile(
            key: ValueKey('member-${m.id}'),
            leading: AppAvatar(
              name: m.name,
              photoUrl: m.text('photoUrl'),
              size: AppDimensions.touch,
            ),
            title: m.name,
            subtitle: l.roleMember,
            onTap: () => context.push('/users/member/${m.id}'),
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Column(
      key: const Key('family-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in adminProfile) card(p),
        for (final (_, tile) in sorted) tile,
        for (final request in pending)
          EntryTile(
            key: ValueKey('invite-${request.id}'),
            leading: AppAvatar(
              name: request.text('recipientName'),
              photoUrl: request.text('recipientPhotoUrl'),
              size: AppDimensions.touch,
            ),
            title: request.text('recipientName'),
            subtitle: l.invitePendingShort,
            onTap: () => confirmAndRun(
              context,
              title: l.cancelInvitation,
              body: l.cancelInvitationBody,
              confirmLabel: l.cancelInvitation,
              operation: () => ref.read(repositoryProvider).mutate(
                'cancelMembershipRequest',
                {'id': request.id},
              ),
            ),
          ),
        if (guest != null) card(guest),
      ],
    );
  }
}

class _MembershipResponse extends ConsumerStatefulWidget {
  const _MembershipResponse({required this.id, required this.name});
  final String id, name;
  @override
  ConsumerState<_MembershipResponse> createState() =>
      _MembershipResponseState();
}

class _MembershipResponseState extends ConsumerState<_MembershipResponse> {
  bool busy = false;
  Future<void> respond(bool accept) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).mutate('respondMembership', {
        'id': widget.id,
        'accept': accept,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppModalSheet(
    title: widget.name,
    description: context.l.membershipAcceptHelp,
    actions: [
      AppButton(
        label: context.l.acceptMembership,
        busy: busy,
        onPressed: () => respond(true),
      ),
      AppButton(
        label: context.l.declineMembership,
        onPressed: busy ? null : () => respond(false),
      ),
    ],
  );
}
