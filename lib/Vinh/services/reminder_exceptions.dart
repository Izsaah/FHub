/// Exception thrown when security or permission checks fail:
/// - Creator-only deletion
/// - Assignee-only completion
/// - Cross-family access restriction
class ReminderPermissionException implements Exception {
  final String message;
  final String? code;

  const ReminderPermissionException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Alias for security clarity
typedef ReminderSecurityException = ReminderPermissionException;

/// Exception thrown when input data validation fails:
/// - Empty title
/// - Past date/time
/// - Invalid assignee
class ReminderValidationException implements Exception {
  final String message;
  final String? field;

  const ReminderValidationException(this.message, {this.field});

  @override
  String toString() => message;
}

/// Exception thrown when a requested reminder cannot be found
class ReminderNotFoundException implements Exception {
  final String message;

  const ReminderNotFoundException([this.message = 'Reminder not found']);

  @override
  String toString() => message;
}
