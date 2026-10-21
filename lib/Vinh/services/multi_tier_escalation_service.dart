import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/reminder_model.dart';

/// 3 Mốc báo động đa tầng theo tài liệu EPIC Module 6:
/// - Mốc 1 (0h): Đúng giờ hẹn -> Nhắc nhẹ nhàng (âm báo chuẩn, rung nhẹ).
/// - Mốc 2 (+6h): Quá hạn 6 tiếng -> Nhắc rung dồn dập trên máy người nhận.
/// - Mốc 3 (+12h): Quá hạn 12 tiếng -> Rung khẩn cấp lần cuối + Gửi cảnh báo về máy người giao.
enum EscalationTier {
  tier1Due,
  tier2SixHours,
  tier3TwelveHours,
}

class EscalationAlert {
  final EscalationTier tier;
  final String reminderId;
  final String reminderTitle;
  final String recipientName;
  final String creatorName;
  final String message;
  final DateTime timestamp;
  final bool isSimulated;
  final int simulatedSeconds;

  const EscalationAlert({
    required this.tier,
    required this.reminderId,
    required this.reminderTitle,
    required this.recipientName,
    required this.creatorName,
    required this.message,
    required this.timestamp,
    this.isSimulated = false,
    this.simulatedSeconds = 0,
  });

  String get tierDisplayName {
    switch (tier) {
      case EscalationTier.tier1Due:
        return 'Mốc 1: Đúng giờ hẹn (0h)';
      case EscalationTier.tier2SixHours:
        return 'Mốc 2: Quá hạn 6 tiếng (+6h)';
      case EscalationTier.tier3TwelveHours:
        return 'Mốc 3: Báo động 12 tiếng (+12h)';
    }
  }

  String get severityLabel {
    switch (tier) {
      case EscalationTier.tier1Due:
        return 'Nhắc nhẹ';
      case EscalationTier.tier2SixHours:
        return 'Nhắc Rung lần 1';
      case EscalationTier.tier3TwelveHours:
        return 'Rung & Báo người giao';
    }
  }
}

/// Dịch vụ quản lý Cơ chế Nhắc lịch Đa tầng (0h -> 6h -> 12h)
/// & Bộ mô phỏng Demo 10 giây (10-Second Simulation Mode).
class MultiTierEscalationService {
  MultiTierEscalationService._();
  static final MultiTierEscalationService instance =
      MultiTierEscalationService._();

  final Map<String, List<Timer>> _activeTimers = {};
  Timer? _demoTimer;
  StreamController<EscalationAlert>? _demoAlertController;

  /// Đặt lịch 3 mốc thời gian thực tế:
  /// - task_0h: đúng giờ hẹn (nhắc nhẹ)
  /// - task_6h: scheduledTime + 6 tiếng (nhắc rung lần 1)
  /// - task_12h: scheduledTime + 12 tiếng (nhắc rung lần 2 + báo về người giao)
  void scheduleMultiTierEscalation(ReminderModel reminder) {
    cancelEscalation(reminder.id);

    final dueDt = reminder.dueDateTime;
    if (dueDt == null || reminder.isCompleted || reminder.isDeleted) {
      return;
    }

    final now = DateTime.now();
    final timers = <Timer>[];

    // 1. Mốc 0h (Đúng giờ hẹn)
    final diff0h = dueDt.difference(now);
    if (!diff0h.isNegative) {
      timers.add(Timer(diff0h, () {
        _triggerTierAlert(reminder, EscalationTier.tier1Due);
      }));
    }

    // 2. Mốc +6h (Quá hạn 6 tiếng)
    final dt6h = dueDt.add(const Duration(hours: 6));
    final diff6h = dt6h.difference(now);
    if (!diff6h.isNegative) {
      timers.add(Timer(diff6h, () {
        _triggerTierAlert(reminder, EscalationTier.tier2SixHours);
      }));
    }

    // 3. Mốc +12h (Quá hạn 12 tiếng)
    final dt12h = dueDt.add(const Duration(hours: 12));
    final diff12h = dt12h.difference(now);
    if (!diff12h.isNegative) {
      timers.add(Timer(diff12h, () {
        _triggerTierAlert(reminder, EscalationTier.tier3TwelveHours);
      }));
    }

    if (timers.isNotEmpty) {
      _activeTimers[reminder.id] = timers;
    }
  }

  /// Tự động hủy toàn bộ các mốc hẹn giờ rung (+6h và +12h) khi bấm Complete
  void cancelEscalation(String reminderId) {
    final timers = _activeTimers.remove(reminderId);
    if (timers != null) {
      for (final t in timers) {
        t.cancel();
      }
    }
  }

  /// Hủy toàn bộ tất cả timers đang active
  void cancelAll() {
    for (final timers in _activeTimers.values) {
      for (final t in timers) {
        t.cancel();
      }
    }
    _activeTimers.clear();
  }

  /// Kiểm tra xem lời nhắc có timers đa tầng đang chạy không
  bool hasActiveEscalation(String reminderId) =>
      _activeTimers.containsKey(reminderId);

  /// Kích hoạt rung và phát thông báo theo từng tầng
  void _triggerTierAlert(ReminderModel reminder, EscalationTier tier) {
    try {
      switch (tier) {
        case EscalationTier.tier1Due:
          // Nhắc nhẹ: Rung nhẹ 1 nhịp
          HapticFeedback.lightImpact();
          debugPrint(
              '🔔 [Escalation 0h] Đến giờ thực hiện: ${reminder.title}');
          break;

        case EscalationTier.tier2SixHours:
          // Quá hạn 6h: Rung mạnh 2 nhịp dồn dập
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 250), () {
            try {
              HapticFeedback.heavyImpact();
            } catch (_) {}
          });
          debugPrint(
              '⚠️ [Escalation +6h] Quá hạn 6 tiếng: Bạn ơi, việc "${reminder.title}" đã quá hạn 6 tiếng rồi!');
          break;

        case EscalationTier.tier3TwelveHours:
          // Quá hạn 12h: Rung dài khẩn cấp + Báo người giao
          HapticFeedback.vibrate();
          Future.delayed(const Duration(milliseconds: 300), () {
            try {
              HapticFeedback.vibrate();
            } catch (_) {}
          });
          debugPrint(
              '🚨 [Escalation +12h] Báo động khẩn: Việc "${reminder.title}" giao cho ${reminder.assignedToName} đã quá 12 tiếng chưa hoàn thành!');
          break;
      }
    } catch (e) {
      debugPrint('ℹ️ HapticFeedback không khả dụng trên nền tảng này: $e');
    }
  }

  /// CHẾ ĐỘ MÔ PHỎNG DEMO 10 GIÂY (10-Second Simulation Mode)
  /// Phục vụ biểu diễn trước thầy cô mà không phải chờ 6 tiếng / 12 tiếng thật:
  /// - Giây 0: Kích hoạt Mốc 1 (Đúng giờ - Nhắc nhẹ)
  /// - Giây 5: Kích hoạt Mốc 2 (Giả lập trễ 6 tiếng - Nhắc rung dồn dập)
  /// - Giây 10: Kích hoạt Mốc 3 (Giả lập trễ 12 tiếng - Rung khẩn cấp + Cảnh báo người giao)
  Stream<EscalationAlert> start10SecondDemo(ReminderModel reminder) {
    stopDemo();

    _demoAlertController = StreamController<EscalationAlert>.broadcast(
      onListen: () {
        scheduleMicrotask(() {
          if (_demoAlertController != null && !_demoAlertController!.isClosed) {
            _emitDemoTier(reminder, EscalationTier.tier1Due, 0);
          }
        });
      },
    );
    int elapsed = 0;

    _demoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      elapsed++;

      if (elapsed == 5) {
        // Sau 5 giây: Giả lập quá hạn 6 tiếng
        _emitDemoTier(reminder, EscalationTier.tier2SixHours, 5);
      } else if (elapsed == 10) {
        // Sau 10 giây: Giả lập quá hạn 12 tiếng
        _emitDemoTier(reminder, EscalationTier.tier3TwelveHours, 10);
        timer.cancel();
      }
    });

    return _demoAlertController!.stream;
  }

  void _emitDemoTier(
      ReminderModel reminder, EscalationTier tier, int seconds) {
    _triggerTierAlert(reminder, tier);

    String message;
    switch (tier) {
      case EscalationTier.tier1Due:
        message = '🔔 Đến giờ hẹn thực hiện "${reminder.title}". Nhắc nhở nhẹ nhàng.';
        break;
      case EscalationTier.tier2SixHours:
        message =
            '⚠️ Bạn ơi, việc "${reminder.title}" đã quá hạn 6 tiếng rồi, bạn đã làm xong chưa?';
        break;
      case EscalationTier.tier3TwelveHours:
        message =
            '🚨 Việc "${reminder.title}" giao cho ${reminder.assignedToName} đã quá 12 tiếng chưa được hoàn thành! Đã kích hoạt cảnh báo rung đến người giao (${reminder.creatorName ?? "Bố Mẹ"}).';
        break;
    }

    final alert = EscalationAlert(
      tier: tier,
      reminderId: reminder.id,
      reminderTitle: reminder.title,
      recipientName: reminder.assignedToName,
      creatorName: reminder.creatorName ?? 'Người giao',
      message: message,
      timestamp: DateTime.now(),
      isSimulated: true,
      simulatedSeconds: seconds,
    );

    _demoAlertController?.add(alert);
  }

  /// Dừng mô phỏng khi người dùng bấm Complete hoặc đóng hộp thoại
  void stopDemo() {
    _demoTimer?.cancel();
    _demoTimer = null;
    _demoAlertController?.close();
    _demoAlertController = null;
  }

  /// Đếm số lời nhắc đang có lịch escalation tích cực
  int get activeEscalationCount => _activeTimers.length;
}
