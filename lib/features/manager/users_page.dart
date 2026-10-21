import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/components.dart';
import '../../core/data/providers.dart';
import 'profile_manage_page.dart';
import 'widgets/entries_view.dart';

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final hasFamily = ref.watch(accountProvider.select((a) => a.asData?.value?.familyId != null));
    final hasGuest = ref.watch(entriesProvider('profiles')).asData?.value.any((p) => p.id == 'guest') ?? true;
    final admin = ref.watch(adminProvider);
    return PageTemplate(
      title: l.familyTitle,
      hasBottomNav: true,
      action: CircularButton(
        label: l.add,
        icon: AppIcons.add,
        size: AppDimensions.touch,
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
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
                          await ref.read(repositoryProvider).mutate('setGuestEnabled', {'enabled': true, 'name': l.profileTypeGuest});
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntryTile(
            title: l.family,
            icon: AppIcons.users,
            onTap: () => context.push('/family'),
          ),
          if (hasFamily && admin)
            EntryTile(
              key: const Key('parental-control'),
              title: l.parentalControl,
              icon: AppIcons.lock,
              onTap: () => context.push('/users/parental'),
            ),
          SectionHeader(l.family),
          EntriesView(
            collection: 'members',
            empty: Text(l.empty),
            builder: (items) => Column(
              children: items
                  .map(
                    (e) => EntryTile(
                      title: e.name,
                      subtitle: e.text('role') == 'admin'
                          ? l.administrator
                          : l.member,
                      onTap: () => context.push('/users/member/${e.id}'),
                    ),
                  )
                  .toList(),
            ),
          ),
          SectionHeader(l.profiles),
          EntriesView(
            collection: 'profiles',
            empty: EmptyState(
              title: l.emptyUsers,
              body: l.noProfilesBody,
              icon: AppIcons.users,
              action: AppButton(label: l.newProfile, onPressed: () => context.push('/users/add')),
            ),
            builder: (items) => Column(
              children: items
                  .map(
                    (e) => EntryTile(
                      title: e.name,
                      subtitle: [
                        profileTypeLabel(context, e.text('type')),
                        if (e.text('type') == 'guest' && e.data['enabled'] == false) l.disabled,
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
