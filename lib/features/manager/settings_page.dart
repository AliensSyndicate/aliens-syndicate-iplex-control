import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/data/app_sharing.dart';
import '../../core/design_system/components.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l,
        value = ref.watch(accountProvider).value?.locale ?? 'system';
    return Scaffold(
      body: PageTemplate(
        title: l.settings,
        showBack: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSurface(
              child: AppDropdownField<String>(
                initialValue: value,
                label: l.language,
                items: [
                  DropdownMenuItem(value: 'system', child: Text(l.systemLanguage)),
                  const DropdownMenuItem(value: 'en', child: Text('English')),
                  const DropdownMenuItem(
                    value: 'pt_BR',
                    child: Text('Português brasileiro'),
                  ),
                  const DropdownMenuItem(value: 'es', child: Text('Español')),
                ],
                onChanged: (v) async {
                  try {
                    await ref.read(repositoryProvider).mutate('savePreferences', {
                      'locale': v,
                    });
                  } catch (e) {
                    if (context.mounted) showFailure(context, e);
                  }
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            NeumorphicListTile(title: l.shareApplication, icon: AppIcons.link, onTap: () async {
              try { await AppSharing.share(AppSharing.message('iPlex', l.provisionalShareMessage)); }
              catch (e) { if (context.mounted) showFailure(context, e); }
            }),
            NeumorphicSectionHeader(l.legal),
            NeumorphicListTile(
              title: l.terms,
              icon: AppIcons.file,
              onTap: () => context.push('/legal/terms'),
            ),
            NeumorphicListTile(
              title: l.privacy,
              icon: AppIcons.lock,
              onTap: () => context.push('/legal/privacy'),
            ),
          ],
        ),
      ),
    );
  }
}
