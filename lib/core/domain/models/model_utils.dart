import 'package:cloud_firestore/cloud_firestore.dart';

/// Utility methods for robust Firestore data conversion.
class ModelUtils {
  const ModelUtils._();

  static DateTime? parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String) return DateTime.tryParse(value);
    try {
      final dynamic v = value;
      if (v.toDate is Function) {
        return v.toDate() as DateTime;
      }
    } catch (_) {}
    return null;
  }

  static dynamic toTimestampOrNull(DateTime? date) {
    if (date == null) return null;
    return Timestamp.fromDate(date);
  }
}
