import 'package:flutter/foundation.dart';
import 'model_utils.dart';

/// Representation of a family subscription in `subscriptions/{subscriptionId}`.
/// Grants playback rights. Manager access remains free regardless of status.
@immutable
class SubscriptionModel {
  const SubscriptionModel({
    required this.id,
    required this.familyId,
    this.status = 'not_started',
    this.plan = 'monthly',
    this.trialStartedAt,
    this.trialEndsAt,
    this.currentPeriodEndsAt,
    this.updatedAt,
  });

  final String id;
  final String familyId;
  final String status; // 'not_started' | 'trialing' | 'active' | 'cancelled' | 'expired'
  final String plan;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEndsAt;
  final DateTime? updatedAt;

  bool canPlay(DateTime now) {
    if (status == 'trialing' || status == 'trial') {
      return trialEndsAt != null && trialEndsAt!.isAfter(now);
    }
    if (status == 'active' || status == 'cancelled') {
      return currentPeriodEndsAt != null && currentPeriodEndsAt!.isAfter(now);
    }
    return false;
  }

  bool isTrialing(DateTime now) {
    return (status == 'trialing' || status == 'trial') &&
        trialEndsAt != null &&
        trialEndsAt!.isAfter(now);
  }

  bool get isActive => status == 'active';

  factory SubscriptionModel.fromMap(String id, Map<String, dynamic> data) {
    final rawStatus = (data['status'] ?? 'not_started') as String;
    final normalizedStatus = rawStatus == 'trial' ? 'trialing' : rawStatus;

    return SubscriptionModel(
      id: id,
      familyId: (data['familyId'] ?? '') as String,
      status: normalizedStatus,
      plan: (data['plan'] ?? 'monthly') as String,
      trialStartedAt: ModelUtils.parseDateTime(data['trialStartedAt']),
      trialEndsAt: ModelUtils.parseDateTime(data['trialEndsAt']),
      currentPeriodEndsAt: ModelUtils.parseDateTime(
        data['currentPeriodEndsAt'] ?? data['paidUntil'],
      ),
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'status': status,
      'plan': plan,
      if (trialStartedAt != null)
        'trialStartedAt': ModelUtils.toTimestampOrNull(trialStartedAt),
      if (trialEndsAt != null)
        'trialEndsAt': ModelUtils.toTimestampOrNull(trialEndsAt),
      if (currentPeriodEndsAt != null)
        'currentPeriodEndsAt': ModelUtils.toTimestampOrNull(currentPeriodEndsAt),
      if (updatedAt != null)
        'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  SubscriptionModel copyWith({
    String? id,
    String? familyId,
    String? status,
    String? plan,
    DateTime? trialStartedAt,
    DateTime? trialEndsAt,
    DateTime? currentPeriodEndsAt,
    DateTime? updatedAt,
  }) {
    return SubscriptionModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      status: status ?? this.status,
      plan: plan ?? this.plan,
      trialStartedAt: trialStartedAt ?? this.trialStartedAt,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      currentPeriodEndsAt: currentPeriodEndsAt ?? this.currentPeriodEndsAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          familyId == other.familyId &&
          status == other.status &&
          plan == other.plan &&
          trialStartedAt == other.trialStartedAt &&
          trialEndsAt == other.trialEndsAt &&
          currentPeriodEndsAt == other.currentPeriodEndsAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        familyId,
        status,
        plan,
        trialStartedAt,
        trialEndsAt,
        currentPeriodEndsAt,
        updatedAt,
      );
}
