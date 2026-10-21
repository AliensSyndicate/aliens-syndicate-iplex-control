import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/providers.dart';
import '../../../../core/design_system/components.dart';
import '../../data/models/iptv_sync_job_model.dart';
import '../../data/repositories/iptv_repository_impl.dart';
import '../../domain/repositories/iptv_repository.dart';

final iptvRepositoryProvider = Provider<IptvRepository>((ref) {
  final managerRepo = ref.watch(repositoryProvider);
  return IptvRepositoryImpl(managerRepository: managerRepo);
});

/// Stream of all currently active (queued, running, pending) IPTV sync jobs for the active scope.
final activeIptvSyncJobsProvider =
    StreamProvider.autoDispose<List<IptvSyncJobModel>>((ref) {
      final repo = ref.watch(repositoryProvider);
      if (!repo.configured) {
        return Stream.value(const []);
      }

      final scopeId = ref.watch(
        accountProvider.select((val) => val.asData?.value?.iptvScopeId),
      );
      if (scopeId == null || scopeId.isEmpty) {
        return Stream.value(const []);
      }

      return ref
          .watch(iptvRepositoryProvider)
          .watchActiveSyncJobs(scopeId)
          .map(
            (list) => list
                .map(
                  (e) => e is IptvSyncJobModel
                      ? e
                      : IptvSyncJobModel(
                          jobId: e.jobId,
                          familyId: e.familyId,
                          sourceId: e.sourceId,
                          requestedByUid: e.requestedByUid,
                          status: e.status,
                          stage: e.stage,
                          progress: e.progress,
                          messageCode: e.messageCode,
                          startedAt: e.startedAt,
                          finishedAt: e.finishedAt,
                          errorCode: e.errorCode,
                          createdAt: e.createdAt,
                          updatedAt: e.updatedAt,
                        ),
                )
                .toList(),
          );
    }, retry: (retryCount, error) => null);

@immutable
class GlobalSyncProgressState {
  const GlobalSyncProgressState({
    required this.isActive,
    required this.isIndeterminate,
    required this.progress,
    required this.activeCount,
    this.stage,
    this.message,
  });

  final bool isActive;
  final bool isIndeterminate;
  final double? progress; // 0.0 to 1.0 or null if indeterminate
  final int activeCount;
  final String? stage;
  final String? message;

  const GlobalSyncProgressState.idle()
    : isActive = false,
      isIndeterminate = false,
      progress = null,
      activeCount = 0,
      stage = null,
      message = null;
}

/// Computes combined global progress across all active sync jobs.
final globalIptvSyncProgressProvider =
    Provider.autoDispose<GlobalSyncProgressState>((ref) {
      final activeJobsAsync = ref.watch(activeIptvSyncJobsProvider);
      final jobs = activeJobsAsync.asData?.value ?? const [];

      if (jobs.isEmpty) {
        return const GlobalSyncProgressState.idle();
      }

      // If any job has null progress or is in queued stage, present indeterminate
      final hasIndeterminate =
          jobs.length > 1 ||
          jobs.any(
            (j) =>
                j.isIndeterminate || j.stage == 'queued' || j.progress == null,
          );

      if (hasIndeterminate) {
        return GlobalSyncProgressState(
          isActive: true,
          isIndeterminate: true,
          progress: null,
          activeCount: jobs.length,
          stage: jobs.first.stage,
          message: jobs.first.messageCode,
        );
      }

      final progress = (jobs.single.progress ?? 0).clamp(0, 100) / 100.0;

      return GlobalSyncProgressState(
        isActive: true,
        isIndeterminate: false,
        progress: progress,
        activeCount: jobs.length,
        stage: jobs.first.stage,
        message: jobs.first.messageCode,
      );
    });

/// Maps real backend error codes to user-friendly messages.
String mapIptvErrorCodeToMessage(BuildContext context, String? errorCode) {
  final l = context.l;
  switch (errorCode) {
    case 'invalid-source-url':
      return l.errorInvalidSourceUrl;
    case 'unrecognized-source-format':
      return l.errorUnrecognizedSourceFormat;
    case 'invalid-credentials':
      return l.errorInvalidCredentials;
    case 'provider-unavailable':
      return l.errorCannotConnect;
    case 'provider-rate-limited':
      return l.errorProviderRateLimited;
    case 'provider-time-budget':
      return l.errorProviderTimeBudget;
    case 'download-failed':
      return l.errorDownloadFailed;
    case 'catalog-too-large':
      return l.errorCatalogTooLarge;
    case 'invalid-catalog':
      return l.errorInvalidPlaylist;
    case 'suspicious-catalog':
      return l.errorSuspiciousCatalog;
    case 'duplicate-content':
      return l.errorDuplicateContent;
    case 'hls-origin-required':
      return l.errorHlsOriginRequired;
    case 'parsing-failed':
      return l.errorParsingFailed;
    case 'normalization-failed':
      return l.errorNormalizationFailed;
    case 'storage-upload-failed':
      return l.errorStorageUploadFailed;
    case 'catalog-publication-failed':
      return l.errorCatalogPublicationFailed;
    case 'catalog-sync-failed':
      return l.errorCatalogSyncFailed;
    case 'unsafe-provider':
      return l.errorUnsafeProvider;
    case 'timeout':
      return l.errorConnectionTimeout;
    case 'invalid-epg':
      return l.errorInvalidEpg;
    case 'catalog-integrity':
      return l.errorCatalogIntegrity;
    case 'worker-retries-exhausted':
      return l.errorWorkerRetriesExhausted;
    case 'source-secret-unavailable':
      return l.errorSourceSecretUnavailable;
    default:
      return l.errorTemporaryProcessing;
  }
}

/// Tracks displayed sync notification job IDs to prevent duplicate bottom sheets.
class SyncNotificationNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  bool hasShown(String jobId) => state.contains(jobId);

  void markAsShown(String jobId) {
    state = {...state, jobId};
  }

  void reset() {
    state = <String>{};
  }
}

final syncNotificationTrackerProvider =
    NotifierProvider<SyncNotificationNotifier, Set<String>>(
      SyncNotificationNotifier.new,
    );
