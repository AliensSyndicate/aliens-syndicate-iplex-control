import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/components.dart';
import '../../core/data/providers.dart';
import '../../core/domain/models.dart';
import '../../app/presence.dart';
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
                builder: (c) => AppModalSheet(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SheetHeader(icon: AppIcons.users, title: l.add),
                      SheetActionRow(
                        key: const Key('add-member'),
                        icon: AppIcons.qr,
                        label: l.invite,
                        onTap: () {
                          Navigator.pop(c);
                          context.push('/users/invite');
                        },
                      ),
                      SheetActionRow(
                        key: const Key('add-profile'),
                        icon: AppIcons.add,
                        label: l.newProfile,
                        onTap: () {
                          Navigator.pop(c);
                          context.push('/users/add');
                        },
                      ),
                      if (hasFamily && !hasGuest)
                        SheetActionRow(
                          key: const Key('add-guest'),
                          icon: AppIcons.account,
                          label: l.addGuest,
                          onTap: () async {
                            Navigator.pop(c);
                            try {
                              await ref.read(repositoryProvider).mutate(
                                'setGuestEnabled',
                                {'enabled': true, 'name': l.profileTypeGuest},
                              );
                            } catch (e) {
                              if (context.mounted) showFailure(context, e);
                            }
                          },
                        ),
                    ],
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

/// The family always has a member (the account that created it): one tile per
/// member, the administrator included, then the invitations still pending.
/// Adding members is the "+" of the top bar, as on Devices and IPTV.
class _FamilyMembers extends ConsumerWidget {
  const _FamilyMembers();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final account = ref.watch(accountProvider).asData?.value;
    final admin = ref.watch(adminProvider);
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
        final now = ref.watch(clockProvider).asData?.value ?? DateTime.now();
        final pending =
            sent?.asData?.value.where(
              (r) => r.number('expiresAt') > now.millisecondsSinceEpoch,
            ) ??
            const <Entry>[];
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
                // On / off and the date it was last on (the account using
                // the app is on now).
                lines: [
                  if (entry.id == account?.uid)
                    formatCardDateTime(context, now)
                  else if (entry.number('lastActiveAt') > 0)
                    formatCardDateTime(
                      context,
                      DateTime.fromMillisecondsSinceEpoch(
                        entry.number('lastActiveAt').toInt(),
                      ),
                    )
                  else
                    l.neverOnline,
                ],
                trailing: () {
                  final on =
                      entry.id == account?.uid ||
                      memberOnline(entry.number('lastActiveAt'), now);
                  return OnOffDot(on: on, label: on ? l.online : l.offline);
                }(),
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
                  operation: () => ref.read(repositoryProvider).mutate(
                    'cancelMembershipRequest',
                    {'id': request.id},
                  ),
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
