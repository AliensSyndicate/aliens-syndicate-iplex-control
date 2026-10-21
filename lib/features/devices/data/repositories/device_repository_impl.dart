import '../../../../core/domain/models.dart';
import '../../../../core/domain/models/device_model.dart';
import '../../../../core/domain/repository.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/entities/pairing_session_entity.dart';
import '../../domain/repositories/device_repository.dart';

class DeviceRepositoryImpl implements DeviceRepository {
  DeviceRepositoryImpl(this._managerRepository);
  final ManagerRepository _managerRepository;

  DeviceEntity _toEntity(DeviceModel model) {
    return DeviceEntity(
      id: model.id,
      familyId: model.familyId,
      displayName: model.displayName,
      platform: model.platform,
      status: model.status,
      manufacturer: model.manufacturer,
      model: model.model,
      nativeIdentityFingerprint: model.nativeIdentityFingerprint,
      identitySource: model.identitySource,
      identityScope: model.identityScope,
      identityStability: model.identityStability,
      linkedAt: model.linkedAt,
      lastSeenAt: model.lastSeenAt,
      linkedByUid: model.linkedByUid,
      onlineUntil: model.onlineUntil,
      sessionId: model.sessionId,
      createdAt: model.createdAt,
      updatedAt: model.updatedAt,
    );
  }

  @override
  Stream<List<DeviceEntity>> watchDevices(String familyId) {
    return _managerRepository.watchEntries(familyId, 'devices').map((entries) {
      final list = entries.map((e) {
        final model = DeviceModel.fromMap(e.id, e.data);
        return _toEntity(model);
      }).toList();
      // Sort: Online devices first, then descending by linkedAt or displayName
      list.sort((a, b) {
        final aTime = a.linkedAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.linkedAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
      return list;
    });
  }

  @override
  Stream<DeviceEntity?> watchDevice(String familyId, String deviceId) {
    return _managerRepository.watchEntry(familyId, 'devices', deviceId).map((
      e,
    ) {
      if (e == null) return null;
      return _toEntity(DeviceModel.fromMap(e.id, e.data));
    });
  }

  @override
  Future<PairingSessionEntity> inspectPairingSession({
    String? token,
    String? code,
  }) async {
    final payload = <String, dynamic>{'token': ?token, 'code': ?code};
    final result = await _managerRepository.mutate(
      'inspectPairingSession',
      payload,
    );
    return PairingSessionEntity.fromMap(result);
  }

  @override
  Future<DeviceEntity> linkDevice({
    String? token,
    String? code,
    String? name,
  }) async {
    final trimmedName = name?.trim();
    final payload = <String, dynamic>{
      'token': ?token,
      'code': ?code,
      if (trimmedName != null && trimmedName.isNotEmpty) 'name': trimmedName,
    };
    final result = await _managerRepository.mutate('linkDevice', payload);
    return DeviceEntity(
      id: (result['id'] ?? '') as String,
      familyId: '',
      displayName: (result['displayName'] ?? name ?? '') as String,
      platform: (result['platform'] ?? 'android_tv') as String,
      status: (result['status'] ?? 'linked') as String,
    );
  }

  @override
  Future<void> renameDevice(String deviceId, String newName) async {
    await _managerRepository.mutate('renameDevice', {
      'id': deviceId,
      'name': newName.trim(),
    });
  }

  @override
  Future<void> unlinkDevice(String deviceId) async {
    await _managerRepository.mutate('deleteDevice', {'id': deviceId});
  }
}
