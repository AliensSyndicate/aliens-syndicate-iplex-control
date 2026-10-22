import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/payments/subscription_checkout.dart';
import 'bottom_navigation.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _rootRoutes = {
    '/home',
    '/search',
    '/users',
    '/devices',
    '/iptv',
    '/account',
  };

  /// Shell branch of each menu item (Home, Busca, Família, Dispositivos,
  /// IPTV). The account branch (4) is reached from the Home avatar.
  static const menuBranches = [0, 5, 1, 2, 3];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final isRoot = _rootRoutes.contains(location);

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          shell,
          const _PurchaseUpdates(),
          if (isRoot)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomNavigation(
                selected: menuBranches.indexOf(shell.currentIndex) < 0
                    ? null
                    : menuBranches.indexOf(shell.currentIndex),
                onSelected: (i) => shell.goBranch(
                  menuBranches[i],
                  initialLocation: menuBranches[i] == shell.currentIndex,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Keeps the store's purchase stream observed for the whole session (when
/// checkout is allowed), so purchases that complete later are verified and
/// acknowledged without waiting for the subscription page to be opened.
class _PurchaseUpdates extends ConsumerWidget {
  const _PurchaseUpdates();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(paymentsConfigProvider).asData?.value.checkoutAllowed ==
        true) {
      ref.watch(checkoutControllerProvider);
    }
    return const SizedBox.shrink();
  }
}
