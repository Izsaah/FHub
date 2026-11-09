// lib/Vinh/services/quiet_hours_engine.dart

/// Cấu hình kênh thông báo theo loại tác vụ
class NotificationChannelConfig {
  final String channelId;
  final String soundFileName;
  final bool enableTtsReadout;
  final bool isQuietHoursImmune;

  const NotificationChannelConfig({
    required this.channelId,
    required this.soundFileName,
    required this.enableTtsReadout,
    required this.isQuietHoursImmune,
  });
}

/// Động cơ xử lý Giờ giới nghiêm (Quiet Hours: 22h00 - 06h00)
/// - Việc nhà thông thường (ASSIGN, FAVOR): Dời báo thức sang 07h00 sáng.
/// - Việc Chăm sóc / Thuốc men (CARE): Miễn trừ giới nghiêm tuyệt đối, kích hoạt chính xác giờ hẹn.
class QuietHoursEngine {
  const QuietHoursEngine();

  DateTime calculateEffectiveAlarmTime({
    required DateTime scheduledTime,
    required String taskType,
  }) {
    if (taskType.toUpperCase() == 'CARE') {
      return scheduledTime;
    }

    final h = scheduledTime.hour;
    if (h >= 22) {
      final nextDay = scheduledTime.add(const Duration(days: 1));
      return DateTime(nextDay.year, nextDay.month, nextDay.day, 7, 0, 0);
    } else if (h < 6) {
      return DateTime(scheduledTime.year, scheduledTime.month, scheduledTime.day, 7, 0, 0);
    }

    return scheduledTime;
  }

  NotificationChannelConfig getNotificationChannelConfig({required String taskType}) {
    if (taskType.toUpperCase() == 'CARE') {
      return const NotificationChannelConfig(
        channelId: 'CARE_CHANNEL',
        soundFileName: 'nhac_uong_thuoc.mp3',
        enableTtsReadout: true,
        isQuietHoursImmune: true,
      );
    }
    return const NotificationChannelConfig(
      channelId: 'DEFAULT_CHANNEL',
      soundFileName: 'default_chime.mp3',
      enableTtsReadout: false,
      isQuietHoursImmune: false,
    );
  }
}
