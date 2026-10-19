import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

extension LocalizedContext on BuildContext {
  AppLocalizations get l => AppLocalizations.of(this);
}
