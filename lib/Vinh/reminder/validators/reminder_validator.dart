import 'package:flutter/material.dart';
import '../models/family_member.dart';

class ReminderValidator {
  static const String futureTimeErrorMessage = 'Reminder time must be in the future.';

  /// Maximum allowed title length for security and UI consistency
  static const int maxTitleLength = 120;

  /// Sanitizes input string to prevent injection / formatting bugs
  static String sanitizeTitle(String? input) {
    if (input == null) return '';
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // Strip HTML tags
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize multiple spaces
        .trim();
  }

  /// Validates reminder title:
  /// - required
  /// - trim
  /// - not empty
  /// - max length <= 120
  static String? validateTitle(String? value) {
    if (value == null) {
      return 'Title is required';
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Title is required';
    }
    if (trimmed.length > maxTitleLength) {
      return 'Title cannot exceed $maxTitleLength characters';
    }
    return null;
  }

  /// Validates assigned member:
  /// - required
  /// - must belong to current Family
  static String? validateAssignedMember(
    String? memberId,
    List<FamilyMember> currentFamilyMembers,
  ) {
    if (memberId == null || memberId.trim().isEmpty) {
      return 'Assigned member is required';
    }
    final isBelongToFamily = currentFamilyMembers.any((m) => m.id == memberId);
    if (!isBelongToFamily) {
      return 'Assigned member must belong to current Family';
    }
    return null;
  }

  /// Validates date selection
  static String? validateDate(DateTime? date) {
    if (date == null) {
      return 'Date is required';
    }
    return null;
  }

  /// Validates time selection
  static String? validateTime(TimeOfDay? time) {
    if (time == null) {
      return 'Time is required';
    }
    return null;
  }

  /// Validates that combined Date + Time is in the future.
  /// If in the past or now, returns:
  /// "Reminder time must be in the future."
  static String? validateFutureDateTime(
    DateTime? date,
    TimeOfDay? time, {
    DateTime? now,
  }) {
    if (date == null) {
      return 'Date is required';
    }
    if (time == null) {
      return 'Time is required';
    }

    final scheduledDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    final currentTime = now ?? DateTime.now();

    if (!scheduledDateTime.isAfter(currentTime)) {
      return futureTimeErrorMessage;
    }

    return null;
  }

  /// Helper to validate parsed strings: date ("dd/MM/yyyy") and time ("HH:mm")
  static String? validateFutureDateTimeFromStrings(
    String? dateStr,
    String? timeStr, {
    DateTime? now,
  }) {
    if (dateStr == null || dateStr.trim().isEmpty) {
      return 'Date is required';
    }
    if (timeStr == null || timeStr.trim().isEmpty) {
      return 'Time is required';
    }

    try {
      final dateParts = dateStr.trim().split('/');
      final timeParts = timeStr.trim().split(':');

      if (dateParts.length != 3 || timeParts.length != 2) {
        return 'Invalid date or time format';
      }

      final day = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final scheduledDateTime = DateTime(year, month, day, hour, minute);
      final currentTime = now ?? DateTime.now();

      if (!scheduledDateTime.isAfter(currentTime)) {
        return futureTimeErrorMessage;
      }
    } catch (_) {
      return 'Invalid date or time format';
    }

    return null;
  }
}
