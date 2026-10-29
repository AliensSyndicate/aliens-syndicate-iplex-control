import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/app_sharing.dart';
import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'widgets/account_avatar.dart';
import 'widgets/public_identity_sheet.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});
  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  bool busy = false;

  static const _languages = ['system', 'pt_BR', 'en', 'es'];

  static String _languageName(AppLocalizations l, String? locale) =>
      switch (locale) {
        'pt_BR' => 'Português brasileiro',
        'en' => 'English',
        'es' => 'Español',
        _ => l.systemLanguage,
      };

  /// Language list in a sheet; the choice is saved in the account.
  Future<void> _pickLanguage(String? current) async {
    final l = context.l;
    final picked = await showAppModalSheet<String>(
      context: context,
      builder: (sheet) => AppModalSheet(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(icon: AppIcons.language, title: l.language),
            for (final code in _languages)
              SelectionRow(
                key: ValueKey('language-option-$code'),
                title: _languageName(l, code),
                selected: code == (current ?? 'system'),
                onTap: () => Navigator.of(sheet).pop(code),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == (current ?? 'system')) return;
    try {
      await ref.read(repositoryProvider).mutate('savePreferences', {
        'locale': picked,
      });
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> operation(bool deletion) async {
    // An administrator must remove the members first: say so before asking
    // for a new login (the backend enforces the same rule).
    final uid = ref.read(accountProvider).value?.uid;
    if (deletion &&
        ref.read(adminProvider) &&
        (ref.read(entriesProvider('members')).asData?.value ?? const []).any(
          (m) => m.id != uid,
        )) {
      showFailure(context, const AppFailure('family-has-members'));
      return;
    }
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
    if (admin && a?.familyId != null) ref.watch(entriesProvider('members'));
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
                const AccountAvatar(),
                const SizedBox(width: AppSpacing.lg),
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
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      Text(
                        a?.familyId == null
                            ? l.unlinkedAccount
                            : admin
                            ? l.administrator
                            : l.member,
                        style: const TextStyle(color: AppColors.accent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          EntryTile(
            title: l.subscription,
            icon: AppIcons.subscription,
            onTap: () => context.push('/account/subscription'),
          ),
          EntryTile(
            key: const Key('account-language'),
            title: l.language,
            subtitle: _languageName(l, a?.locale),
            icon: AppIcons.language,
            onTap: () => _pickLanguage(a?.locale),
          ),
          EntryTile(
            title: l.help,
            icon: AppIcons.help,
            onTap: () => context.push('/account/help'),
          ),
          EntryTile(
            title: l.about,
            icon: AppIcons.info,
            onTap: () => context.push('/account/about'),
          ),
          EntryTile(
            key: const Key('share-app'),
            title: l.shareApplication,
            icon: AppIcons.share,
            onTap: () async {
              try {
                await AppSharing.share(
                  AppSharing.message('iPlex', l.provisionalShareMessage),
                );
              } catch (e) {
                if (context.mounted) showFailure(context, e);
              }
            },
          ),
          SectionHeader(l.legal),
          EntryTile(
            title: l.terms,
            icon: AppIcons.terms,
            onTap: () => context.push('/legal/terms'),
          ),
          EntryTile(
            title: l.privacy,
            icon: AppIcons.privacy,
            onTap: () => context.push('/legal/privacy'),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: l.logout,
            busy: busy,
            onPressed: () => operation(false),
          ),
          const SizedBox(height: AppSpacing.lg),
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
