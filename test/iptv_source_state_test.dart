import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/widgets/iptv_source_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// IPTV state everywhere: green on, red no connection / any failure, grey off.
void main() {
  IptvSourceState state(Map<String, Object?> data) =>
      iptvSourceState(Entry('s', data));

  test('on: ready and enabled', () {
    expect(state({'status': 'ready'}), IptvSourceState.on);
    expect(state({'status': 'online', 'enabled': true}), IptvSourceState.on);
  });

  test('failure: error, retry, offline or never synced', () {
    expect(state({'status': 'error'}), IptvSourceState.failure);
    expect(
      state({'status': 'queued', 'errorCode': 'provider-unavailable'}),
      IptvSourceState.failure,
    );
    expect(state({'status': 'offline'}), IptvSourceState.failure);
    expect(state({'status': 'queued'}), IptvSourceState.failure);
  });

  test('off: disabled wins over any other state', () {
    expect(state({'status': 'ready', 'enabled': false}), IptvSourceState.off);
    expect(state({'status': 'error', 'enabled': false}), IptvSourceState.off);
  });

  test('syncing: spinner', () {
    expect(state({'status': 'syncing'}), IptvSourceState.syncing);
  });
}
