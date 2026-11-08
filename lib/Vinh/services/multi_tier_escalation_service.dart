import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../main.dart';
import '../../Danh/services/notification_service.dart';
import '../models/reminder_model.dart';
import '../widgets/due_reminder_alert_dialog.dart';
import 'alarm_sound_service.dart';
import 'quiet_hours_engine.dart';

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

/// Dịch vụ quản lý Cơ chế Nhắc lịch Đa tầng (0h -> 6h -> 12h),
/// Đồng hồ Realtime tự động chuyển trạng thái Quá hạn mỗi giây,
/// & Bộ mô phỏng Demo 10 giây (10-Second Simulation Mode).
class MultiTierEscalationService {
  MultiTierEscalationService._();
  static final MultiTierEscalationService instance =
      MultiTierEscalationService._();

  final QuietHoursEngine quietHoursEngine = const QuietHoursEngine();
  final Map<String, List<Timer>> _activeTimers = {};
  Timer? _demoTimer;
  StreamController<EscalationAlert>? _demoAlertController;

  /// Bộ đếm nhịp đồng hồ thời gian thực (cập nhật mỗi 1 giây) để UI tự động chuyển từ "còn 1p" sang "QUÁ HẠN"
  /// ngay tại giây :00 mà không cần tạo lại Firestore Stream hay bấm lại icon Lời nhắc.
  final ValueNotifier<DateTime> clockTick =
      ValueNotifier<DateTime>(DateTime.now());
  Timer? _globalClockTimer;
  List<ReminderModel> _trackedReminders = [];
  BuildContext? _lastContext;
  void Function(ReminderModel)? _lastOnOpenDetail;

  /// Tập hợp các reminderId đã được thấy ở trạng thái CHỜ THỰC HIỆN (chưa quá hạn)
  final Set<String> _previouslyPendingIds = {};

  /// Tập hợp các reminderId đã được phát chuông & hiện popup khi đến hạn (tránh hiện lặp lại liên tục)
  final Set<String> _alertedDueReminderIds = {};
  Set<String> get alertedDueReminderIds => _alertedDueReminderIds;
  String? _currentlyRingingReminderId;

  /// Hàng đợi các lời nhắc đến hạn chờ hiển thị popup tuần tự
  final List<ReminderModel> _pendingAlertQueue = [];

  /// Khởi động bộ đếm đồng hồ 1 giây toàn cục nếu chưa chạy
  void ensureClockRunning() {
    if (_globalClockTimer != null && _globalClockTimer!.isActive) return;
    _globalClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      clockTick.value = now;
      if (_trackedReminders.isNotEmpty) {
        _evaluateDueReminders(
          _trackedReminders,
          now: now,
          context: _lastContext,
          onOpenDetail: _lastOnOpenDetail,
        );
      }
    });
  }

  /// Đặt lịch 3 mốc thời gian thực tế:
  /// - task_0h: đúng giờ hẹn (nhắc nhẹ, có áp dụng Quiet Hours nếu không phải CARE)
  /// - task_6h: scheduledTime + 6 tiếng (nhắc rung lần 1)
  /// - task_12h: scheduledTime + 12 tiếng (nhắc rung lần 2 + báo về người giao)
  void scheduleMultiTierEscalation(ReminderModel reminder) {
    cancelEscalation(reminder.id);

    final rawDueDt = reminder.dueDateTime;
    if (rawDueDt == null || reminder.isCompleted || reminder.isDeleted) {
      return;
    }

    final dueDt = quietHoursEngine.calculateEffectiveAlarmTime(
      scheduledTime: rawDueDt,
      taskType: reminder.taskType.dbValue,
    );

    final now = DateTime.now();
    final timers = <Timer>[];

    // 1. Mốc 0h (Đúng giờ hẹn)
    final diff0h = dueDt.difference(now);
    if (!diff0h.isNegative) {
      timers.add(Timer(diff0h, () {
        clockTick.value = DateTime.now();
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

  /// Kích hoạt chuông reo báo thức và hiển thị Khung Thông Báo Nổi (Due Alert Dialog)
  /// Luôn chạy hiển thị Dialog trong PostFrameCallback để an toàn tuyệt đối kể cả khi gọi từ build().
  void triggerDueAlarmAndPopup(
    ReminderModel reminder, {
    BuildContext? context,
    void Function(ReminderModel)? onOpenDetail,
  }) {
    if (_alertedDueReminderIds.contains(reminder.id)) return;
    _alertedDueReminderIds.add(reminder.id);

    if (context != null) _lastContext = context;
    if (onOpenDetail != null) _lastOnOpenDetail = onOpenDetail;

    // 1. Kích hoạt chuông reo báo thức (Bell Chime) & rung ngay lập tức
    _currentlyRingingReminderId = reminder.id;
    AlarmSoundService.instance.startAlarm();

    // 2. Bắn thông báo In-app vào Notification Hub
    unawaited(
      NotificationService.instance.addNotification(
        familyId: reminder.familyId,
        targetUserId: reminder.assignedTo,
        title: '⏰ Đến giờ: ${reminder.title}!',
        titleEn: '⏰ Task Due: ${reminder.title}!',
        body:
            'Nhiệm vụ "${reminder.title}" giao cho ${reminder.assignedToName} đã đến giờ thực hiện (${reminder.time}). Hãy hoàn tất ngay nhé!',
        bodyEn:
            'Task "${reminder.title}" assigned to ${reminder.assignedToName} is due now (${reminder.time}). Please complete it!',
        type: 'task_due',
      ),
    );

    // 3. Đưa vào hàng đợi hiển thị Khung Thông Báo Nổi sau khi frame render xong
    if (!_pendingAlertQueue.any((r) => r.id == reminder.id)) {
      _pendingAlertQueue.add(reminder);
    }
    _scheduleProcessAlertQueue();
  }

  void _scheduleProcessAlertQueue() {
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processNextAlertInQueue();
      });
    } catch (_) {
      _processNextAlertInQueue();
    }
  }

  Future<void> _processNextAlertInQueue() async {
    if (DueReminderAlertDialog.isShowing || _pendingAlertQueue.isEmpty) {
      return;
    }

    BuildContext? targetContext = navigatorKey.currentContext ?? _lastContext;
    if (targetContext != null && !targetContext.mounted) {
      targetContext = navigatorKey.currentContext;
    }
    if (targetContext == null || !targetContext.mounted) {
      return;
    }

    final nextReminder = _pendingAlertQueue.removeAt(0);
    await DueReminderAlertDialog.show(
      targetContext,
      reminder: nextReminder,
      onOpenDetail: _lastOnOpenDetail,
    );

    // Nếu còn task khác cũng đến hạn trong hàng đợi thì hiển thị tiếp
    if (_pendingAlertQueue.isNotEmpty) {
      _scheduleProcessAlertQueue();
    }
  }

  /// Quét đồng bộ danh sách lời nhắc để tự động hẹn giờ và kiểm tra nhiệm vụ đến hạn
  void syncReminders(
    List<ReminderModel> reminders, {
    BuildContext? context,
    void Function(ReminderModel)? onOpenDetail,
  }) {
    _trackedReminders = reminders;
    if (context != null) _lastContext = context;
    if (onOpenDetail != null) _lastOnOpenDetail = onOpenDetail;

    ensureClockRunning();
    _evaluateDueReminders(
      reminders,
      now: DateTime.now(),
      context: context,
      onOpenDetail: onOpenDetail,
    );
  }

  void _evaluateDueReminders(
    List<ReminderModel> reminders, {
    required DateTime now,
    BuildContext? context,
    void Function(ReminderModel)? onOpenDetail,
  }) {
    for (final r in reminders) {
      if (r.isCompleted || r.isDeleted || r.isSubmitted) {
        _previouslyPendingIds.remove(r.id);
        cancelEscalation(r.id);
        continue;
      }

      final dt = r.dueDateTime;
      if (dt == null) continue;

      if (!dt.isAfter(now)) {
        // Task đã chạm hoặc vượt mốc giờ hẹn (now >= dt)
        final diff = now.difference(dt);
        final justTransitionedFromPending =
            _previouslyPendingIds.remove(r.id);

        // Nếu task vừa chuyển từ Chờ thực hiện -> Quá hạn ngay trước mắt người dùng,
        // hoặc vừa mới đến hạn trong vòng 15 phút gần nhất:
        if ((justTransitionedFromPending || diff.inMinutes < 15) &&
            !_alertedDueReminderIds.contains(r.id)) {
          triggerDueAlarmAndPopup(
            r,
            context: context ?? _lastContext,
            onOpenDetail: onOpenDetail ?? _lastOnOpenDetail,
          );
        }
      } else {
        // Task vẫn đang ở tương lai (Chờ thực hiện) -> ghi nhận để khi vừa điểm giờ sẽ báo ngay
        _previouslyPendingIds.add(r.id);
        if (!hasActiveEscalation(r.id)) {
          scheduleMultiTierEscalation(r);
        }
      }
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
    _pendingAlertQueue.removeWhere((r) => r.id == reminderId);
    if (_currentlyRingingReminderId == reminderId) {
      _currentlyRingingReminderId = null;
      AlarmSoundService.instance.stopAlarm();
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
    _alertedDueReminderIds.clear();
    _previouslyPendingIds.clear();
    _pendingAlertQueue.clear();
    _currentlyRingingReminderId = null;
    _trackedReminders = [];
    _globalClockTimer?.cancel();
    _globalClockTimer = null;
    AlarmSoundService.instance.stopAlarm();
  }

  /// Kiểm tra xem lời nhắc có timers đa tầng đang chạy không
  bool hasActiveEscalation(String reminderId) =>
      _activeTimers.containsKey(reminderId);

  /// Kích hoạt rung và phát thông báo theo từng tầng
  void _triggerTierAlert(ReminderModel reminder, EscalationTier tier) {
    try {
      switch (tier) {
        case EscalationTier.tier1Due:
          triggerDueAlarmAndPopup(reminder);
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
          unawaited(
            NotificationService.instance.addNotification(
              familyId: reminder.familyId,
              targetUserId: reminder.assignedTo,
              title: '⚠️ Quá hạn 6 tiếng: ${reminder.title}!',
              titleEn: '⚠️ 6h Overdue: ${reminder.title}!',
              body:
                  'Nhiệm vụ "${reminder.title}" đã quá hạn 6 tiếng chưa được nộp nghiệm thu. Hãy kiểm tra lại!',
              bodyEn:
                  'Task "${reminder.title}" is 6 hours overdue. Please check and complete!',
              type: 'task_overdue_6h',
            ),
          );
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
          unawaited(
            NotificationService.instance.addNotification(
              familyId: reminder.familyId,
              title: '🚨 Báo động quá hạn 12 tiếng: ${reminder.title}!',
              titleEn: '🚨 12h Overdue Alert: ${reminder.title}!',
              body:
                  'Việc "${reminder.title}" giao cho ${reminder.assignedToName} đã quá hạn hơn nửa ngày chưa hoàn tất!',
              bodyEn:
                  'Task "${reminder.title}" assigned to ${reminder.assignedToName} has been overdue for 12 hours!',
              type: 'task_overdue_12h',
            ),
          );
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
