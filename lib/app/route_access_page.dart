import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system/components.dart';

class RouteAccessPage extends StatelessWidget {
  const RouteAccessPage({super.key, required this.familyRequired});
  final bool familyRequired;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageTemplate(
      title: familyRequired ? context.l.family : context.l.accessDenied,
      showBack: true,
      child: EmptyState(
        title: familyRequired ? context.l.manageFamily : context.l.accessDenied,
        body: familyRequired
            ? context.l.familyRequiredBody
            : context.l.memberSetupHint,
        icon: AppIcons.users,
        action: Column(
          children: [
            AppButton(
              label: context.l.familyTitle,
              onPressed: () => context.go('/users'),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: context.l.home,
              onPressed: () => context.go('/home'),
            ),
          ],
        ),
      ),
    ),
  );
}
