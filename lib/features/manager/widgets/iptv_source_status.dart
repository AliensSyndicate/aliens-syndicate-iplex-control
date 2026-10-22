import 'package:flutter/material.dart';

import '../../../core/design_system/components.dart';
import '../../../core/domain/models.dart';

/// State of an IPTV source, the same everywhere (list card, details page,
/// Home picker): green on, red no connection or any failure, grey off.
enum IptvSourceState { on, failure, off, syncing }

IptvSourceState iptvSourceState(Entry source) {
  if (source.data['enabled'] == false) return IptvSourceState.off;
  final status = source.text('status');
  // Any failure (final or being retried) is red.
  if (status == 'error' || source.text('errorCode').isNotEmpty) {
    return IptvSourceState.failure;
  }
  if (status == 'syncing' || status == 'validating') {
    return IptvSourceState.syncing;
  }
  if (status == 'ready' || status == 'online') return IptvSourceState.on;
  // Not available (offline, never synced): no connection.
  return IptvSourceState.failure;
}

/// The state dot (spinner while syncing), described for screen readers.
class IptvSourceIndicator extends StatelessWidget {
  const IptvSourceIndicator({super.key, required this.source});
  final Entry source;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final state = iptvSourceState(source);
    final retrying =
        source.text('status') == 'queued' &&
        source.text('errorCode').isNotEmpty;
    return Semantics(
      label: switch (state) {
        IptvSourceState.on => l.online,
        IptvSourceState.off => l.disabled,
        IptvSourceState.syncing => l.sourceSyncing,
        IptvSourceState.failure =>
          retrying
              ? l.sourceRetrying
              : source.text('status') == 'error' ||
                    source.text('errorCode').isNotEmpty
              ? l.sourceFailure
              : l.offline,
      },
      child: state == IptvSourceState.syncing
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          : NeumorphicStatusIndicator(
              status: switch (state) {
                IptvSourceState.on => IndicatorStatus.online,
                IptvSourceState.off => IndicatorStatus.offline,
                _ => IndicatorStatus.error,
              },
              color: switch (state) {
                IptvSourceState.on => AppColors.statusOn,
                IptvSourceState.off => AppColors.disabled,
                _ => AppColors.error,
              },
            ),
    );
  }
}
