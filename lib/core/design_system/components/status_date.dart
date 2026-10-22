import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../tokens.dart';
import 'neumorphic_status_indicator.dart';

/// Date and time of the list cards (last sync, last time on): only the
/// date and the time, e.g. "22/10/2026 às 09:00".
String formatCardDateTime(BuildContext context, DateTime time) {
  final locale = Localizations.localeOf(context).toString();
  return (locale.startsWith('pt')
          ? DateFormat("dd/MM/yyyy 'às' HH:mm", locale)
          : DateFormat.yMd(locale).add_Hm())
      .format(time);
}

/// On / off dot of the list cards (devices, family members): green on,
/// grey off — the same colors as the IPTV state.
class OnOffDot extends StatelessWidget {
  const OnOffDot({super.key, required this.on, required this.label});
  final bool on;

  /// Described for screen readers ("Online" / "Offline").
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: NeumorphicStatusIndicator(
      online: on,
      color: on ? AppColors.statusOn : AppColors.disabled,
    ),
  );
}
