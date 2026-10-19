import '../entities/iptv_sync_job_entity.dart';

/// Pure domain interface dedicated to IPTV synchronization operations.
abstract class IptvSyncRepository {
  Stream<List<IptvSyncJobEntity>> watchActiveSyncJobs(String familyId);
  Stream<IptvSyncJobEntity?> watchSyncJob(String jobId);
  Future<Map<String, dynamic>> triggerSync(String sourceId);
}
