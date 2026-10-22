import 'package:flutter/material.dart';

import '../../core/design_system/components.dart';

/// List row of the prototype: square thumbnail, title, secondary line and
/// optional trailing actions.
class MediaListRow extends StatelessWidget {
  const MediaListRow({
    super.key,
    required this.image,
    required this.title,
    this.subtitle = '',
    this.onTap,
    this.trailing,
    this.round = false,
  });
  final Widget image;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Circular thumbnail (people).
  final bool round;

  static const size = 56.0;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(round ? size / 2 : AppRadii.xs),
            child: SizedBox.square(dimension: size, child: image),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

/// Network photo or initials (people).
class PhotoOrInitials extends StatelessWidget {
  const PhotoOrInitials({super.key, required this.name, this.url});
  final String name;
  final String? url;

  Widget _initials() => ColoredBox(
    color: AppColors.surfaceElevated,
    child: Center(
      child: Text(
        name
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w.characters.first.toUpperCase())
            .join(),
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final photo = url;
    if (photo == null) return _initials();
    return Image(
      image: CachedNetworkImage(photo, decodeWidth: 360),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stack) => _initials(),
    );
  }
}
