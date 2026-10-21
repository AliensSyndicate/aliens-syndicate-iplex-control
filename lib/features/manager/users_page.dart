import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/components.dart';
import '../../core/data/providers.dart';
import '../../core/domain/models.dart';
import 'profile_manage_page.dart';
import 'widgets/entries_view.dart';

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final hasFamily = ref.watch(
      accountProvider.select((a) => a.asData?.value?.familyId != null),
    );
    final hasGuest =
        ref
            .watch(entriesProvider('profiles'))
            .asData
            ?.value
            .any((p) => p.id == 'guest') ??
        true;
    final admin = ref.watch(adminProvider);
    return PageTemplate(
      title: l.familyTitle,
      hasBottomNav: true,
      action: admin
          ? CircularButton(
              label: l.add,
              icon: AppIcons.add,
              size: AppDimensions.touch,
              onPressed: () => showAppModalSheet<void>(
                context: context,
                builder: (c) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EntryTile(
                          title: l.invite,
                          icon: AppIcons.qr,
                          onTap: () {
                            Navigator.pop(c);
                            context.push('/users/invite');
                          },
                        ),
                        EntryTile(
                          title: l.newProfile,
                          icon: AppIcons.add,
                          onTap: () {
                            Navigator.pop(c);
                            context.push('/users/add');
                          },
                        ),
                        if (hasFamily && !hasGuest)
                          EntryTile(
                            key: const Key('add-guest'),
                            title: l.addGuest,
                            icon: AppIcons.account,
                            onTap: () async {
                              Navigator.pop(c);
                              try {
                                await ref
                                    .read(repositoryProvider)
                                    .mutate('setGuestEnabled', {
                                      'enabled': true,
                                      'name': l.profileTypeGuest,
                                    });
                              } catch (e) {
                                if (context.mounted) showFailure(context, e);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ReceivedInvitations(),
          const _FamilyMembers(),
          if (hasFamily && admin)
            EntryTile(
              key: const Key('parental-control'),
              title: l.parentalControl,
              icon: AppIcons.lock,
              onTap: () => context.push('/users/parental'),
            ),
          if (hasFamily && !admin)
            EntryTile(
              key: const Key('link-to-profile'),
              title: l.linkToProfile,
              icon: AppIcons.link,
              onTap: () => context.push('/family/link-profile'),
            ),
          SectionHeader(l.profiles),
          EntriesView(
            collection: 'profiles',
            empty: EmptyState(
              title: l.emptyUsers,
              body: l.noProfilesBody,
              icon: AppIcons.users,
              action: AppButton(
                label: l.newProfile,
                onPressed: () => context.push('/users/add'),
              ),
            ),
            builder: (items) => Column(
              children: items
                  .map(
                    (e) => EntryTile(
                      title: e.name,
                      subtitle: [
                        profileTypeLabel(context, e.text('type')),
                        if (e.text('type') == 'guest' &&
                            e.data['enabled'] == false)
                          l.disabled,
                      ].join(' · '),
                      onTap: () => context.push('/users/${e.id}'),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Name shown for the family: individual families carry the account holder's name.
String _familyName(BuildContext context, Family? family) {
  final l = context.l;
  if (family == null || family.name.isEmpty) return l.familyTitle;
  return family.individual ? l.familyOfName(family.name) : family.name;
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

/// Empty state (same pattern as IPTV without sources) while the family has only its
/// administrator; otherwise one tile per member, then the invitations still pending.
class _FamilyMembers extends ConsumerWidget {
  const _FamilyMembers();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final account = ref.watch(accountProvider).asData?.value;
    final admin = ref.watch(adminProvider);
    final family = ref.watch(familyProvider).asData?.value;
    if (account?.familyId == null) return const AppLoadingSkeleton();
    final members = ref.watch(entriesProvider('members'));
    final sent = admin ? ref.watch(entriesProvider('sentInvitations')) : null;
    return members.when(
      skipLoadingOnRefresh: false,
      skipLoadingOnReload: false,
      loading: () => const AppLoadingSkeleton(),
      error: (e, s) =>
          ErrorState(onRetry: () => ref.invalidate(entriesProvider('members'))),
      data: (items) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final pending =
            sent?.asData?.value.where((r) => r.number('expiresAt') > now) ??
            const <Entry>[];
        if (admin && items.length <= 1 && pending.isEmpty) {
          return EmptyState(
            title: _familyName(context, family),
            body: l.familyEmptyBody,
            action: AppButton(
              label: l.addMembers,
              icon: AppIcons.add,
              onPressed: () => context.push('/users/invite'),
            ),
          );
        }
        return Column(
          children: [
            for (final entry in items)
              EntryTile(
                key: ValueKey('member-${entry.id}'),
                leading: AppAvatar(
                  name: entry.name,
                  photoUrl: entry.text('photoUrl'),
                  size: AppDimensions.touch,
                ),
                title: entry.name,
                subtitle: entry.text('role') == 'admin'
                    ? l.administrator
                    : l.member,
                // Administrators manage members; a member only opens its own entry (to leave).
                onTap:
                    (admin && entry.text('role') != 'admin') ||
                        (!admin &&
                            entry.id == account?.uid &&
                            entry.text('role') != 'admin')
                    ? () => context.push('/users/member/${entry.id}')
                    : null,
              ),
            for (final request in pending)
              EntryTile(
                key: ValueKey('invite-${request.id}'),
                leading: AppAvatar(
                  name: request.text('recipientName'),
                  photoUrl: request.text('recipientPhotoUrl'),
                  size: AppDimensions.touch,
                ),
                title: request.text('recipientName'),
                subtitle: l.invitePending,
                onTap: () => confirmAndRun(
                  context,
                  title: l.cancelInvitation,
                  body: l.cancelInvitationBody,
                  confirmLabel: l.cancelInvitation,
                  operation: () => ref
                      .read(repositoryProvider)
                      .mutate('cancelMembershipRequest', {'id': request.id}),
                ),
              ),
          ],
        );
      },
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
