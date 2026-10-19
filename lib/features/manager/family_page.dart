import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import 'widgets/entries_view.dart';
import 'widgets/family_scope.dart';

class FamilyPage extends ConsumerWidget {
  const FamilyPage({super.key});

  Future<void> select(BuildContext context, WidgetRef ref, String? id) async {
    try {
      await ref.read(repositoryProvider).mutate('selectContext', {'familyId': id});
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final account = ref.watch(accountProvider).asData?.value;
    final hasFamily = account?.familyId != null;
    final ids = account?.memberships ?? [];

    Widget buildInvitations() => EntriesView(
      collection: 'invitations',
      empty: const SizedBox.shrink(),
      builder: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(l.membershipRequests),
          ...items.map((request) => EntryTile(
            title: request.text('familyName'),
            icon: AppIcons.users,
            onTap: () => showAppModalSheet<void>(
              context: context,
              title: request.text('familyName'),
              description: l.membershipAcceptHelp,
              builder: (c) => _MembershipResponse(
                id: request.id,
                name: request.text('familyName'),
              ),
            ),
          )),
        ],
      ),
    );

    return Scaffold(
      body: PageTemplate(
        title: l.familyTitle,
        showBack: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildInvitations(),
            EntryTile(
              key: const Key('link-to-profile'),
              title: l.linkToProfile,
              icon: AppIcons.link,
              onTap: () => context.push('/family/link-profile'),
            ),
            if (ids.length > 1) ...[
              for (final id in ids)
                ref.watch(availableFamilyProvider(id)).when(
                  loading: () => const AppLoadingSkeleton(rows: 1),
                  error: (e, s) => ErrorState(
                    onRetry: () => ref.invalidate(availableFamilyProvider(id)),
                  ),
                  data: (family) => family == null
                      ? const SizedBox.shrink()
                      : EntryTile(
                          title: family.name.isEmpty ? l.family : family.name,
                          subtitle:
                              '${family.isAdmin(account!.uid) ? l.administrator : l.member}${account.familyId == id ? ' · ${l.selectedContext}' : ''}',
                          icon: AppIcons.users,
                          onTap: () => select(context, ref, id),
                        ),
                ),
              const SizedBox(height: AppTokens.md),
            ],
            if (hasFamily)
              FamilyScope(
                child: Column(
                  children: [
                    EntriesView(
                      collection: 'members',
                      empty: Text(l.empty),
                      builder: (items) => Column(
                        children: items
                            .map(
                              (entry) => EntryTile(
                                title: entry.name,
                                subtitle: entry.text('role') == 'admin'
                                    ? l.administrator
                                    : l.member,
                                onTap: () =>
                                    context.push('/users/member/${entry.id}'),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    if (ref.watch(adminProvider)) ...[
                      const SizedBox(height: AppTokens.lg),
                      AppButton(
                        label: l.invite,
                        icon: AppIcons.qr,
                        onPressed: () => context.push('/users/invite'),
                      ),
                    ],
                  ],
                ),
              )
            else
              EmptyState(
                title: l.emptyUsers,
                body: l.familyIntro,
                action: AppButton(
                  label: l.createFamily,
                  onPressed: () => context.push('/family/create'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MembershipResponse extends ConsumerStatefulWidget {
  const _MembershipResponse({required this.id, required this.name});
  final String id, name;
  @override
  ConsumerState<_MembershipResponse> createState() => _MembershipResponseState();
}

class _MembershipResponseState extends ConsumerState<_MembershipResponse> {
  bool busy = false;
  Future<void> respond(bool accept) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).mutate('respondMembership', {'id': widget.id, 'accept': accept});
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
