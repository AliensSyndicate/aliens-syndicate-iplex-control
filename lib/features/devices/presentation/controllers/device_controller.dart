import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/providers.dart';
import '../../data/repositories/device_repository_impl.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/entities/pairing_session_entity.dart';
import '../../domain/repositories/device_repository.dart';

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  final managerRepository = ref.watch(repositoryProvider);
  return DeviceRepositoryImpl(managerRepository);
});

final familyDevicesStreamProvider = StreamProvider<List<DeviceEntity>>((ref) {
  final familyId = ref.watch(accountProvider).asData?.value?.resourceScopeId;
  if (familyId == null || familyId.isEmpty) {
    return Stream.value(const []);
  }
  final repo = ref.watch(deviceRepositoryProvider);
  return repo.watchDevices(familyId);
});

final deviceDetailStreamProvider = StreamProvider.family<DeviceEntity?, String>(
  (ref, deviceId) {
    final familyId = ref.watch(accountProvider).asData?.value?.resourceScopeId;
    if (familyId == null || familyId.isEmpty) {
      return Stream.value(null);
    }
    final repo = ref.watch(deviceRepositoryProvider);
    return repo.watchDevice(familyId, deviceId);
  },
);

class DevicePairingState {
  const DevicePairingState({
    this.inspecting = false,
    this.linking = false,
    this.session,
    this.linkedDevice,
    this.error,
  });

  final bool inspecting;
  final bool linking;
  final PairingSessionEntity? session;
  final DeviceEntity? linkedDevice;
  final Object? error;

  DevicePairingState copyWith({
    bool? inspecting,
    bool? linking,
    PairingSessionEntity? session,
    DeviceEntity? linkedDevice,
    Object? error,
  }) {
    return DevicePairingState(
      inspecting: inspecting ?? this.inspecting,
      linking: linking ?? this.linking,
      session: session ?? this.session,
      linkedDevice: linkedDevice ?? this.linkedDevice,
      error: error,
    );
  }
}

class DevicePairingNotifier extends Notifier<DevicePairingState> {
  @override
  DevicePairingState build() => const DevicePairingState();

  Future<PairingSessionEntity?> inspect({String? token, String? code}) async {
    state = state.copyWith(inspecting: true, error: null);
    try {
      final repo = ref.read(deviceRepositoryProvider);
      final session = await repo.inspectPairingSession(
        token: token,
        code: code,
      );
      state = state.copyWith(inspecting: false, session: session);
      return session;
    } catch (e) {
      state = state.copyWith(inspecting: false, error: e);
      rethrow;
    }
  }

  Future<DeviceEntity> confirmLink({String? customName}) async {
    final currentSession = state.session;
    state = state.copyWith(linking: true, error: null);
    try {
      final repo = ref.read(deviceRepositoryProvider);
      final device = await repo.linkDevice(
        token: currentSession?.token,
        name: customName ?? currentSession?.displayName,
      );
      state = state.copyWith(linking: false, linkedDevice: device);
      return device;
    } catch (e) {
      state = state.copyWith(linking: false, error: e);
      rethrow;
    }
  }

  void reset() {
    state = const DevicePairingState();
  }
}

final devicePairingProvider =
    NotifierProvider<DevicePairingNotifier, DevicePairingState>(
      DevicePairingNotifier.new,
    );
