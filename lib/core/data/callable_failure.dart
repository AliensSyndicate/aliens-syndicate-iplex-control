import '../domain/models.dart';

/// Preserve stable domain codes while falling back to the transport code when
/// the SDK supplies a generic or descriptive message. Never display raw messages.
AppFailure callableFailure({
  required String code,
  String? message,
  Object? details,
}) => AppFailure(
  message != null && RegExp(r'^[a-z]+(?:-[a-z]+)*$').hasMatch(message)
      ? message
      : code,
  details is Map ? Map<String, dynamic>.from(details) : const {},
);
