import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';

/// The authenticated account's avatar. The main menu and the Account screen both
/// read it from `accountProvider`, so they always show the same user and photo.
class AccountAvatar extends ConsumerWidget {
  const AccountAvatar({super.key, this.size = AppDimensions.avatar});
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).asData?.value;
    return AppAvatar(
      name: account?.name ?? '',
      photoUrl: account?.photoUrl,
      size: size,
    );
  }
}

/// Avatar content for the Account button of the main menu (inside the button surface).
class AccountAvatarFace extends ConsumerWidget {
  const AccountAvatarFace({super.key, required this.size});
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).asData?.value;
    return AppAvatarFace(
      name: account?.name ?? '',
      photoUrl: account?.photoUrl,
      size: size,
    );
  }
}
