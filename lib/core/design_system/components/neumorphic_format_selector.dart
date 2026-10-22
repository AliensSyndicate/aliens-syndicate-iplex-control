import 'package:flutter/material.dart';

import '../icons.dart';
import '../localized_context.dart';
import '../tokens.dart';
import 'app_tabs.dart';

class FormatOption {
  const FormatOption({
    required this.id,
    required this.label,
    required this.icon,
  });
  final String id;
  final String label;
  final List<List<dynamic>> icon;
}

/// IPTV format selector: the shared [AppTabs] (no parallel style).
class NeumorphicFormatSelector extends StatelessWidget {
  const NeumorphicFormatSelector({
    super.key,
    required this.selectedFormat,
    required this.onFormatSelected,
    this.disabled = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.xs,
    ),
  });

  final String selectedFormat;
  final ValueChanged<String> onFormatSelected;
  final bool disabled;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final options = [
      FormatOption(id: 'url', label: l.sourceFormatUrl, icon: AppIcons.link),
      FormatOption(id: 'file', label: l.sourceFormatFile, icon: AppIcons.file),
      FormatOption(
        id: 'xtream',
        label: l.sourceFormatXtream,
        icon: AppIcons.server,
      ),
      FormatOption(
        id: 'other_m3u8',
        label: l.sourceFormatOtherM3u8,
        icon: AppIcons.play,
      ),
    ];

    // Same tabs as everywhere else (reference: Busca).
    return AppTabs<String>(
      padding: padding,
      enabled: !disabled,
      options: [for (final o in options) (o.id, o.label)],
      selected: selectedFormat == 'm3u' ? 'url' : selectedFormat,
      onSelected: (id) {
        final current = selectedFormat == 'm3u' ? 'url' : selectedFormat;
        if (!disabled && id != current) onFormatSelected(id);
      },
    );
  }
}
