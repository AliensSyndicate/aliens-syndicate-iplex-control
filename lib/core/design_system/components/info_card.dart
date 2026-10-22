import 'package:flutter/material.dart';

import '../tokens.dart';
import 'neumorphic_list_tile.dart';

/// Card of a managed resource (devices, IPTV): the list card
/// ([NeumorphicListTile]): icon in the card circle (light when active), a status
/// line, optional extra lines and the status on the right, centered.
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.status,
    this.extra,
    this.footnote,
    this.active = false,
    this.statusColor,
    this.dot,
    this.trailing,
    this.titlePrefix,
  });
  final List<List<dynamic>> icon;
  final String title;
  final String? status, extra;

  /// Last line (e.g. last sync).
  final String? footnote;

  /// Connected / online: highlighted icon box.
  final bool active;

  /// Overrides the status line color (errors, syncing).
  final Color? statusColor;

  /// Status dot on the right.
  final Widget? dot;

  /// Replaces the dot (e.g. a spinner while syncing).
  final Widget? trailing;

  /// Small mark before the title (e.g. a lock).
  final Widget? titlePrefix;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => NeumorphicListTile(
    title: title,
    titlePrefix: titlePrefix,
    subtitle: status,
    subtitleColor: statusColor,
    lines: [?extra, ?footnote],
    trailing: trailing ?? dot,
    onTap: onTap,
    icon: icon,
    iconColor: active ? AppColors.primary : AppColors.textSecondary,
  );
}
