import '../entities/iptv_source_entity.dart';
import '../entities/iptv_sync_job_entity.dart';
import 'iptv_sync_repository.dart';

abstract class IptvRepository implements IptvSyncRepository {
  @override
  Stream<List<IptvSyncJobEntity>> watchActiveSyncJobs(String familyId);
  @override
  Stream<IptvSyncJobEntity?> watchSyncJob(String jobId);
  Stream<IptvSourceEntity?> watchIptvSource(String sourceId);
  Stream<List<Map<String, dynamic>>> watchPendingNotifications(String uid);
  Future<void> markNotificationDelivered(String uid, String jobId);
  Future<void> registerFcmToken(String uid, String token, {String? platform});
  @override
  Future<Map<String, dynamic>> triggerSync(String sourceId);
  Future<Map<String, dynamic>> saveSource(Map<String, dynamic> payload);
}
