import '../entities/device_entity.dart';
import '../entities/pairing_session_entity.dart';

abstract class DeviceRepository {
  Stream<List<DeviceEntity>> watchDevices(String familyId);
  Stream<DeviceEntity?> watchDevice(String familyId, String deviceId);
  Future<PairingSessionEntity> inspectPairingSession({
    String? token,
    String? code,
  });
  Future<DeviceEntity> linkDevice({String? token, String? code, String? name});
  Future<void> renameDevice(String deviceId, String newName);
  Future<void> unlinkDevice(String deviceId);
}
