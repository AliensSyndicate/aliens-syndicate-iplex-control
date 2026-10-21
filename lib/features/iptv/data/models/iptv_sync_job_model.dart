import 'package:flutter/foundation.dart';

import '../../../../core/domain/models/model_utils.dart';
import '../../domain/entities/iptv_sync_job_entity.dart';

@immutable
class IptvSyncJobModel extends IptvSyncJobEntity {
  const IptvSyncJobModel({
    String? jobId,
    String? id,
    required super.familyId,
    required super.sourceId,
    required super.requestedByUid,
    super.status = 'pending',
    super.stage = 'queued',
    super.progress = 0,
    super.messageCode = 'iptv.sync.queued',
    super.startedAt,
    super.finishedAt,
    super.errorCode,
    super.errorRetryable,
    super.traceId,
    super.createdAt,
    super.updatedAt,
  }) : super(jobId: jobId ?? id ?? '');

  /// Compatibility getter for legacy callers expecting `id`
  String get id => jobId;

  factory IptvSyncJobModel.fromMap(String id, Map<String, dynamic> data) {
    final rawProgress = data['progress'];
    final int? progress = rawProgress is num ? rawProgress.toInt() : null;

    return IptvSyncJobModel(
      jobId: (data['jobId'] ?? id) as String,
      familyId: (data['familyId'] ?? '') as String,
      sourceId: (data['sourceId'] ?? '') as String,
      requestedByUid: (data['requestedByUid'] ?? '') as String,
      status: (data['status'] ?? 'pending') as String,
      stage: (data['stage'] ?? data['status'] ?? 'queued') as String,
      progress: progress,
      messageCode: (data['messageCode'] ?? 'iptv.sync.queued') as String,
      startedAt: ModelUtils.parseDateTime(data['startedAt']),
      finishedAt: ModelUtils.parseDateTime(data['finishedAt']),
      errorCode: data['errorCode'] as String?,
      errorRetryable: data['errorRetryable'] as bool?,
      traceId: data['traceId'] as String?,
      createdAt: ModelUtils.parseDateTime(data['createdAt']),
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'jobId': jobId,
      'familyId': familyId,
      'sourceId': sourceId,
      'requestedByUid': requestedByUid,
      'status': status,
      'stage': stage,
      'progress': progress,
      'messageCode': messageCode,
      'errorCode': errorCode,
      if (errorRetryable != null) 'errorRetryable': errorRetryable,
      if (traceId != null) 'traceId': traceId,
      if (startedAt != null)
        'startedAt': ModelUtils.toTimestampOrNull(startedAt),
      if (finishedAt != null)
        'finishedAt': ModelUtils.toTimestampOrNull(finishedAt),
      if (createdAt != null)
        'createdAt': ModelUtils.toTimestampOrNull(createdAt),
      if (updatedAt != null)
        'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  IptvSyncJobModel copyWith({
    String? jobId,
    String? id,
    String? familyId,
    String? sourceId,
    String? requestedByUid,
    String? status,
    String? stage,
    int? progress,
    String? messageCode,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? errorCode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return IptvSyncJobModel(
      jobId: jobId ?? id ?? this.jobId,
      familyId: familyId ?? this.familyId,
      sourceId: sourceId ?? this.sourceId,
      requestedByUid: requestedByUid ?? this.requestedByUid,
      status: status ?? this.status,
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      messageCode: messageCode ?? this.messageCode,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      errorCode: errorCode ?? this.errorCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
