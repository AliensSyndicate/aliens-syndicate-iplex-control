import 'package:flutter/foundation.dart';

/// Pure domain entity representing an asynchronous IPTV sync job.
@immutable
class IptvSyncJobEntity {
  const IptvSyncJobEntity({
    required this.jobId,
    required this.familyId,
    required this.sourceId,
    required this.requestedByUid,
    this.status = 'queued',
    this.stage = 'queued',
    this.progress = 0,
    this.messageCode = 'iptv.sync.queued',
    this.startedAt,
    this.finishedAt,
    this.errorCode,
    this.errorRetryable,
    this.traceId,
    this.createdAt,
    this.updatedAt,
  });

  final String jobId;
  final String familyId;
  final String sourceId;
  final String requestedByUid;
  final String
  status; // 'queued' | 'running' | 'completed' | 'failed' | 'cancelled'
  final String stage; // 'queued' | 'identifying_server' | 'validating_source' | 'downloading' | 'parsing' | 'normalizing' | 'uploading_catalog' | 'publishing_catalog' | 'completed' | 'failed'
  final int? progress; // 0 to 100, null for indeterminate
  final String messageCode;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? errorCode;
  final bool? errorRetryable;
  final String? traceId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isCompleted => status == 'completed' || stage == 'completed';
  bool get isFailed =>
      status == 'failed' || stage == 'failed' || errorCode != null;
  bool get isRunning =>
      status == 'running' || status == 'queued' || status == 'pending';
  bool get isIndeterminate => progress == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IptvSyncJobEntity &&
          runtimeType == other.runtimeType &&
          jobId == other.jobId &&
          familyId == other.familyId &&
          sourceId == other.sourceId &&
          requestedByUid == other.requestedByUid &&
          status == other.status &&
          stage == other.stage &&
          progress == other.progress &&
          messageCode == other.messageCode &&
          startedAt == other.startedAt &&
          finishedAt == other.finishedAt &&
          errorCode == other.errorCode &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    jobId,
    familyId,
    sourceId,
    requestedByUid,
    status,
    stage,
    progress,
    messageCode,
    startedAt,
    finishedAt,
    errorCode,
    createdAt,
    updatedAt,
  );
}
