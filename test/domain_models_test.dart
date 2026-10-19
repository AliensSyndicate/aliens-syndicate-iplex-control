import 'package:flutter_test/flutter_test.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';

void main() {
  group('CODEX Firestore Domain Models Tests', () {
    final now = DateTime.utc(2026, 10, 18, 12, 0, 0);
    final nowMillis = now.millisecondsSinceEpoch;

    test('UserModel serialization and deserialization', () {
      final user = UserModel(
        uid: 'user-123',
        displayName: 'John Doe',
        photoUrl: 'https://example.com/photo.jpg',
        email: 'john@example.com',
        primaryFamilyId: 'family-1',
        locale: 'pt_BR',
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );

      final map = user.toMap();
      expect(map['uid'], 'user-123');
      expect(map['displayName'], 'John Doe');
      expect(map['primaryFamilyId'], 'family-1');

      final fromMap = UserModel.fromMap('user-123', {
        'name': 'John Doe',
        'email': 'john@example.com',
        'familyId': 'family-1',
        'locale': 'pt_BR',
        'status': 'active',
        'createdAt': nowMillis,
        'updatedAt': nowMillis,
      });

      expect(fromMap.uid, 'user-123');
      expect(fromMap.displayName, 'John Doe');
      expect(fromMap.primaryFamilyId, 'family-1');
      expect(fromMap.isActive, isTrue);
      expect(fromMap.createdAt?.millisecondsSinceEpoch, nowMillis);
    });

    test('FamilyModel serialization and deserialization', () {
      final family = FamilyModel(
        id: 'family-1',
        adminUid: 'admin-123',
        name: 'Santos Family',
        status: 'active',
        maxMembers: 5,
        createdAt: now,
        updatedAt: now,
      );

      expect(family.isAdmin('admin-123'), isTrue);
      expect(family.isAdmin('other-user'), isFalse);
      expect(family.isActive, isTrue);

      final fromMap = FamilyModel.fromMap('family-1', {
        'adminId': 'admin-123',
        'name': 'Santos Family',
        'status': 'active',
        'maxMembers': 5,
        'createdAt': nowMillis,
      });

      expect(fromMap.adminUid, 'admin-123');
      expect(fromMap.name, 'Santos Family');
      expect(fromMap.maxMembers, 5);
    });

    test('FamilyMemberModel roles and active status', () {
      final member = FamilyMemberModel(
        id: 'member-1',
        familyId: 'family-1',
        userUid: 'user-456',
        role: 'member',
        status: 'active',
        joinedAt: now,
      );

      expect(member.isAdmin, isFalse);
      expect(member.isActive, isTrue);

      final adminMember = member.copyWith(role: 'admin');
      expect(adminMember.isAdmin, isTrue);

      final fromMap = FamilyMemberModel.fromMap('member-2', {
        'familyId': 'family-1',
        'userUid': 'user-789',
        'role': 'admin',
        'status': 'active',
        'joinedAt': nowMillis,
      });

      expect(fromMap.isAdmin, isTrue);
      expect(fromMap.familyId, 'family-1');
    });

    test('ProfileModel viewing identity independence', () {
      final profile = ProfileModel(
        id: 'profile-1',
        familyId: 'family-1',
        name: 'Kids Profile',
        avatarKey: 'avatar-kids',
        status: 'active',
        createdByUid: 'admin-123',
        createdAt: now,
      );

      expect(profile.name, 'Kids Profile');
      expect(profile.isActive, isTrue);

      final map = profile.toMap();
      expect(map['familyId'], 'family-1');
      expect(map['avatarKey'], 'avatar-kids');
    });

    test('DeviceModel platform mapping and status', () {
      final tizenDevice = DeviceModel(
        id: 'device-1',
        familyId: 'family-1',
        displayName: 'Samsung Smart TV',
        platform: 'tizen',
        status: 'linked',
        lastSeenAt: now,
        linkedAt: now,
        linkedByUid: 'admin-123',
      );

      expect(tizenDevice.platformLabel, 'Samsung Tizen');
      expect(tizenDevice.isLinked, isTrue);

      final webosDevice = tizenDevice.copyWith(platform: 'webos');
      expect(webosDevice.platformLabel, 'LG webOS');

      final androidDevice = tizenDevice.copyWith(platform: 'android_tv');
      expect(androidDevice.platformLabel, 'Android TV');
    });

    test('IptvSourceModel formats, status and secret isolation', () {
      final source = IptvSourceModel(
        id: 'source-1',
        familyId: 'family-1',
        name: 'My Channels',
        type: 'xtream',
        status: 'ready',
        catalogId: 'catalog-1',
        credentialsRef: 'secrets/family-1_source-1',
        epgEnabled: true,
        pinProtected: true,
        createdByUid: 'admin-123',
        contentCount: 450,
      );

      expect(source.isReady, isTrue);
      expect(source.isSyncing, isFalse);
      expect(source.hasError, isFalse);
      expect(source.type, 'xtream');
      expect(source.credentialsRef, 'secrets/family-1_source-1');

      final mapped = IptvSourceModel.fromMap('source-2', {
        'familyId': 'family-1',
        'name': 'Alternative M3U8',
        'format': 'other_m3u8',
        'status': 'queued',
        'isProtected': true,
        'hasEpg': true,
      });

      expect(mapped.type, 'm3u8_alternative');
      expect(mapped.isSyncing, isTrue);
      expect(mapped.pinProtected, isTrue);
      expect(mapped.epgEnabled, isTrue);
    });

    test('IptvSyncJobModel lifecycle states', () {
      final job = IptvSyncJobModel(
        id: 'job-1',
        familyId: 'family-1',
        sourceId: 'source-1',
        status: 'running',
        requestedByUid: 'admin-123',
        startedAt: now,
      );

      expect(job.isRunning, isTrue);
      expect(job.isCompleted, isFalse);
      expect(job.isFailed, isFalse);

      final failed = job.copyWith(
        status: 'failed',
        errorCode: 'timeout',
        finishedAt: now.add(const Duration(minutes: 1)),
      );
      expect(failed.isFailed, isTrue);
      expect(failed.errorCode, 'timeout');
    });

    test('CatalogModel storage metadata separation', () {
      final catalog = CatalogModel(
        id: 'catalog-1',
        status: 'ready',
        version: 12,
        storagePath: 'catalogs/catalog-1/v12.json',
        contentCount: 1200,
        createdAt: now,
      );

      expect(catalog.version, 12);
      expect(catalog.storagePath, 'catalogs/catalog-1/v12.json');
      expect(catalog.contentCount, 1200);
      expect(catalog.isReady, isTrue);
    });

    test('SubscriptionModel playback evaluation and trial duration', () {
      final activeTrial = SubscriptionModel(
        id: 'sub-1',
        familyId: 'family-1',
        status: 'trialing',
        trialStartedAt: now,
        trialEndsAt: now.add(const Duration(days: 7)),
      );

      expect(activeTrial.canPlay(now.add(const Duration(days: 3))), isTrue);
      expect(activeTrial.canPlay(now.add(const Duration(days: 8))), isFalse);
      expect(activeTrial.isTrialing(now.add(const Duration(days: 3))), isTrue);

      final paidSub = SubscriptionModel(
        id: 'sub-2',
        familyId: 'family-1',
        status: 'active',
        currentPeriodEndsAt: now.add(const Duration(days: 30)),
      );
      expect(paidSub.canPlay(now.add(const Duration(days: 15))), isTrue);
      expect(paidSub.canPlay(now.add(const Duration(days: 35))), isFalse);
    });

    test('PlaybackSessionModel session validity and concurrency limits', () {
      final session = PlaybackSessionModel(
        id: 'sess-1',
        familyId: 'family-1',
        profileId: 'profile-1',
        deviceId: 'device-1',
        status: 'active',
        startedAt: now,
        lastHeartbeatAt: now,
        leaseExpiresAt: now.add(const Duration(seconds: 90)),
      );

      expect(session.isAlive(now.add(const Duration(seconds: 45))), isTrue);
      expect(session.isAlive(now.add(const Duration(seconds: 120))), isFalse);

      final released = session.copyWith(status: 'released');
      expect(released.isAlive(now.add(const Duration(seconds: 45))), isFalse);
    });

    test('ProfileFavoriteModel and ProfileProgressModel determinism', () {
      final favoriteId = ProfileFavoriteModel.generateId('profile-1', 'ch-101');
      expect(favoriteId, 'profile-1_ch-101');

      final favorite = ProfileFavoriteModel(
        id: favoriteId,
        familyId: 'family-1',
        profileId: 'profile-1',
        contentId: 'ch-101',
        title: 'Sports HD',
        createdAt: now,
      );

      expect(favorite.title, 'Sports HD');
      expect(favorite.familyId, 'family-1');

      final progressId = ProfileProgressModel.generateId(
        'profile-1',
        'mov-200',
      );
      final progress = ProfileProgressModel(
        id: progressId,
        familyId: 'family-1',
        profileId: 'profile-1',
        contentId: 'mov-200',
        position: 4500,
        duration: 5000,
        updatedAt: now,
      );

      expect(progress.progressPercentage, 0.9);
      expect(progress.isCompleted, isFalse);

      final completed = progress.copyWith(position: 4900);
      expect(completed.progressPercentage, 0.98);
      expect(completed.isCompleted, isTrue);
    });
  });
}
