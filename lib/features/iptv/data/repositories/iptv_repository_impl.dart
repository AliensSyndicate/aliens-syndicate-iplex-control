import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../../core/domain/repository.dart';
import '../../domain/repositories/iptv_repository.dart';
import '../models/iptv_source_model.dart';
import '../models/iptv_sync_job_model.dart';

class IptvRepositoryImpl implements IptvRepository {
  IptvRepositoryImpl({this.firestore, required this.managerRepository});

  final FirebaseFirestore? firestore;
  final ManagerRepository managerRepository;

  FirebaseFirestore? get _db {
    if (firestore != null) return firestore;
    if (Firebase.apps.isNotEmpty) {
      return FirebaseFirestore.instance;
    }
    return null;
  }

  @override
  Stream<List<IptvSyncJobModel>> watchActiveSyncJobs(String familyId) {
    final db = _db;
    if (familyId.isEmpty || db == null) return Stream.value(const []);

    return db
        .collection('iptv_sync_jobs')
        .where('familyId', isEqualTo: familyId)
        .where(
          'requestedByUid',
          isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
        )
        .where('trigger', isEqualTo: 'manual')
        .where('status', whereIn: ['queued', 'running', 'pending'])
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => IptvSyncJobModel.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<IptvSyncJobModel?> watchSyncJob(String jobId) {
    final db = _db;
    if (jobId.isEmpty || db == null) return Stream.value(null);

    return db
        .doc('iptv_sync_jobs/$jobId')
        .snapshots()
        .map(
          (doc) =>
              doc.exists ? IptvSyncJobModel.fromMap(doc.id, doc.data()!) : null,
        );
  }

  @override
  Stream<IptvSourceModel?> watchIptvSource(String sourceId) {
    final db = _db;
    if (sourceId.isEmpty || db == null) return Stream.value(null);

    return db
        .doc('iptv_sources/$sourceId')
        .snapshots()
        .map(
          (doc) =>
              doc.exists ? IptvSourceModel.fromMap(doc.id, doc.data()!) : null,
        );
  }

  @override
  Stream<List<Map<String, dynamic>>> watchPendingNotifications(String uid) {
    final db = _db;
    if (uid.isEmpty || db == null) return Stream.value(const []);

    return db
        .collection('users/$uid/sync_notifications')
        .where('delivered', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  @override
  Future<void> markNotificationDelivered(String uid, String jobId) async {
    final db = _db;
    if (uid.isEmpty || jobId.isEmpty || db == null) return;

    await db.doc('users/$uid/sync_notifications/$jobId').set({
      'delivered': true,
      'deliveredAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> registerFcmToken(
    String uid,
    String token, {
    String? platform,
  }) async {
    final db = _db;
    if (uid.isEmpty || token.isEmpty || db == null) return;

    await managerRepository.mutate('registerPushToken', {
      'token': token,
      'platform': platform ?? 'flutter',
    });
  }

  @override
  Future<Map<String, dynamic>> triggerSync(String sourceId) async {
    return managerRepository.mutate('syncSource', {'id': sourceId});
  }

  @override
  Future<Map<String, dynamic>> saveSource(Map<String, dynamic> payload) async {
    return managerRepository.mutate('saveSource', payload);
  }
}
