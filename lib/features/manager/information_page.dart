import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';

class InformationPage extends ConsumerWidget {
  const InformationPage({super.key, required this.kind});
  final String kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(accountProvider).value, l = context.l;
    return Scaffold(
      body: PageTemplate(
        title: switch (kind) {
          'profile' => l.myProfile,
          'help' => l.help,
          _ => l.about,
        },
        showBack: true,
        child: AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kind == 'profile') ...[
                Text(
                  a?.name ?? '',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  a?.email ?? '',
                  style: const TextStyle(color: AppTokens.secondary),
                ),
              ] else ...[
                Text(
                  kind == 'help' ? l.configurationRequired : l.aboutBody,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
