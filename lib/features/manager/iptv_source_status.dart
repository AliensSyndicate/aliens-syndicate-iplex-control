import 'package:flutter/material.dart';

import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';

String iptvSourceStatus(BuildContext c, Entry e) => switch (e.text('status')) {
  'ready' => c.l.sourceReady,
  'syncing' => c.l.sourceSyncing,
  'validating' => c.l.sourceValidating,
  'error' => c.l.sourceError,
  _ => c.l.sourceQueued,
};
