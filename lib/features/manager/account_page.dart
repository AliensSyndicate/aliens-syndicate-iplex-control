import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import 'widgets/public_identity_sheet.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});
  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  bool busy = false;
  Future<void> operation(bool deletion) async {
    if (deletion &&
        !await confirmRemoval(
          context,
          title: context.l.deleteAccount,
          body: context.l.deleteAccountBody,
        )) {
      return;
    }
    setState(() => busy = true);
    try {
      if (deletion) {
        await ref.read(repositoryProvider).deleteAccount();
      } else {
        await ref.read(repositoryProvider).signOut();
      }
    } catch (e) {
      if (mounted) {
        showFailure(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l,
        a = ref.watch(accountProvider).value,
        admin = ref.watch(adminProvider);
    return PageTemplate(
      title: l.account,
      hasBottomNav: true,
      action: CircularButton(
        key: const Key('account-public-code'),
        label: l.publicUserCode,
        icon: AppIcons.qr,
        size: AppDimensions.touch,
        onPressed: () => showPublicIdentity(context, a?.publicCode),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSurface(
            child: Row(
              children: [
                AppAvatar(name: a?.name ?? ''),
                const SizedBox(width: AppTokens.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a?.name ?? '',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        a?.email ?? '',
                        style: const TextStyle(color: AppTokens.secondary),
                      ),
                      Text(
                        a?.familyId == null
                            ? l.unlinkedAccount
                            : admin
                            ? l.administrator
                            : l.member,
                        style: const TextStyle(color: AppTokens.accent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.xl),
          EntryTile(
            title: l.myProfile,
            onTap: () => context.push('/account/profile'),
          ),
          EntryTile(
            title: l.subscription,
            onTap: () => context.push('/account/subscription'),
          ),
          EntryTile(
            title: l.preferences,
            icon: AppIcons.settings,
            onTap: () => context.push('/account/settings'),
          ),
          EntryTile(title: l.help, onTap: () => context.push('/account/help')),
          EntryTile(
            title: l.about,
            onTap: () => context.push('/account/about'),
          ),
          const SizedBox(height: AppTokens.lg),
          AppButton(
            label: l.logout,
            busy: busy,
            onPressed: () => operation(false),
          ),
          const SizedBox(height: AppTokens.lg),
          AppButton.red(
            label: l.deleteAccount,
            busy: busy,
            onPressed: () => operation(true),
          ),
        ],
      ),
    );
  }
}
