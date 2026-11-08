import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../main.dart';
import '../../Danh/services/notification_service.dart';
import '../../Thinh/theme/app_language.dart';
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
/// Phân quyền thông báo đúng đối tượng (Người được giao / Người tạo khi việc xung phong ế),
/// Nhắc lại thêm 1 lần sau 30 phút khi bấm "Biết rồi / Bỏ qua",
/// & Bộ mô phỏng Demo 10 giây (10-Second Simulation Mode).
class MultiTierEscalationService {
  MultiTierEscalationService._();
  static final MultiTierEscalationService instance =
      MultiTierEscalationService._();

  final QuietHoursEngine quietHoursEngine = const QuietHoursEngine();
  final Map<String, List<Timer>> _activeTimers = {};
  Timer? _demoTimer;
  StreamController<EscalationAlert>? _demoAlertController;

  /// Thời gian nhắc lại khi người dùng bấm "Biết rồi / Bỏ qua" (mặc định 30 phút)
  /// Dùng nullable + getter/setter để an toàn tuyệt đối khi Hot Reload trên Flutter Web.
  Duration? _snoozeDuration;
  Duration get snoozeDuration =>
      _snoozeDuration ?? const Duration(minutes: 30);
  set snoozeDuration(Duration value) => _snoozeDuration = value;

  /// Bộ đếm nhịp đồng hồ thời gian thực (cập nhật mỗi 1 giây) để UI tự động chuyển từ "còn 1p" sang "QUÁ HẠN"
  /// ngay tại giây :00 mà không cần tạo lại Firestore Stream hay bấm lại icon Lời nhắc.
  final ValueNotifier<DateTime> clockTick =
      ValueNotifier<DateTime>(DateTime.now());
  Timer? _globalClockTimer;
  List<ReminderModel> _trackedReminders = [];
  String? _lastCurrentUserId;
  String? _lastCurrentUserName;
  String? _lastCurrentUserMemberId;
  String? _lastCurrentUserFamilyName;
  BuildContext? _lastContext;
  void Function(ReminderModel)? _lastOnOpenDetail;

  /// Tập hợp các reminderId đã được thấy ở trạng thái CHỜ THỰC HIỆN (chưa quá hạn)
  Set<String>? _previouslyPendingIds;
  Set<String> get _safePreviouslyPendingIds =>
      _previouslyPendingIds ??= <String>{};

  /// Tập hợp các reminderId đã được phát chuông & hiện popup khi đến hạn
  Set<String>? _alertedDueReminderIds;
  Set<String> get alertedDueReminderIds =>
      _alertedDueReminderIds ??= <String>{};
  String? _currentlyRingingReminderId;

  /// Tập hợp các reminderId đã được đồng bộ trạng thái quá hạn lên Firestore
  Set<String>? _syncedOverdueReminderIds;
  Set<String> get _safeSyncedOverdueReminderIds =>
      _syncedOverdueReminderIds ??= <String>{};

  /// Quản lý nhắc lại 1 lần nữa sau 30 phút khi người dùng bấm "Biết rồi / Bỏ qua"
  Set<String>? _snoozedOnceReminderIds;
  Set<String> get snoozedOnceReminderIds =>
      _snoozedOnceReminderIds ??= <String>{};

  Map<String, Timer>? _snoozeTimers;
  Map<String, Timer> get _safeSnoozeTimers =>
      _snoozeTimers ??= <String, Timer>{};

  Map<String, DateTime>? _snoozeDueAt;
  Map<String, DateTime> get snoozeDueAt =>
      _snoozeDueAt ??= <String, DateTime>{};

  Set<String>? _followUpActiveIds;
  Set<String> get _safeFollowUpActiveIds =>
      _followUpActiveIds ??= <String>{};

  /// Hàng đợi các lời nhắc đến hạn chờ hiển thị popup tuần tự
  List<ReminderModel>? _pendingAlertQueue;
  List<ReminderModel> get _safePendingAlertQueue =>
      _pendingAlertQueue ??= <ReminderModel>[];

  String? _resolveCurrentUserId([String? explicitUserId]) {
    if (explicitUserId != null && explicitUserId.isNotEmpty) {
      _lastCurrentUserId = explicitUserId;
      return explicitUserId;
    }
    if (_lastCurrentUserId != null && _lastCurrentUserId!.isNotEmpty) {
      return _lastCurrentUserId;
    }
    if (Firebase.apps.isNotEmpty) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          _lastCurrentUserId = uid;
          return uid;
        }
      } catch (_) {}
    }
    return null;
  }

  bool _matchesUserId(String targetField, String uid) {
    if (targetField.isEmpty || uid.isEmpty) return false;
    if (targetField == uid) return true;
    if (targetField.endsWith('_$uid') || uid.endsWith('_$targetField')) {
      return true;
    }
    if (targetField.contains(uid) || uid.contains(targetField)) {
      return true;
    }
    return false;
  }

  String _normalizeName(String s) {
    var res = s.trim().toLowerCase();
    const accents = {
      'à|á|ạ|ả|ã|â|ầ|ấ|ậ|ẩ|ẫ|ă|ằ|ắ|ặ|ẳ|ẵ': 'a',
      'è|é|ẹ|ẻ|ẽ|ê|ề|ế|ệ|ể|ễ': 'e',
      'ì|í|ị|ỉ|ĩ': 'i',
      'ò|ó|ọ|ỏ|õ|ô|ồ|ố|ộ|ổ|ỗ|ơ|ờ|ớ|ợ|ở|ỡ': 'o',
      'ù|ú|ụ|ủ|ũ|ư|ừ|ứ|ự|ử|ữ': 'u',
      'ỳ|ý|ỵ|ỷ|ỹ': 'y',
      'đ': 'd',
    };
    for (final entry in accents.entries) {
      res = res.replaceAll(RegExp(entry.key), entry.value);
    }
    return res.replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _matchesUserName(String nameA, String nameB) {
    if (nameA.trim().isEmpty || nameB.trim().isEmpty) return false;
    final a = _normalizeName(nameA);
    final b = _normalizeName(nameB);
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;
    final wordsA = a.split(' ').where((w) => w.isNotEmpty).toList();
    final wordsB = b.split(' ').where((w) => w.isNotEmpty).toList();
    if (wordsA.length >= 2 && wordsB.length >= 2) {
      if (wordsA.first == wordsB.first && wordsA.last == wordsB.last) {
        return true;
      }
    }
    return false;
  }

  /// Kiểm tra xem người dùng hiện tại có phải là đối tượng nhận thông báo & chuông reo hay không:
  /// 1. Nếu là nhiệm vụ xung phong chưa ai nhận (`reminder.isOpenTask == true`):
  ///    -> CHỈ hiện thông báo & chuông cho NGƯỜI TẠO (`reminder.creatorId == currentUserId` hoặc tên người tạo khớp).
  /// 2. Nếu là nhiệm vụ đã giao cho thành viên cụ thể (`reminder.isOpenTask == false`):
  ///    -> CHỈ hiện thông báo & chuông cho NGƯỜI ĐƯỢC GIAO (`reminder.assignedTo == currentUserId` hoặc tên người nhận khớp).
  bool shouldNotifyUser(
    ReminderModel reminder, {
    String? currentUserId,
    String? currentUserName,
    String? currentUserMemberId,
    String? currentUserFamilyName,
  }) {
    final uid = _resolveCurrentUserId(currentUserId);
    final uname = (currentUserName ?? _lastCurrentUserName ?? '').trim();
    final memberId = (currentUserMemberId ?? _lastCurrentUserMemberId ?? '').trim();
    final memberName = (currentUserFamilyName ?? _lastCurrentUserFamilyName ?? '').trim();

    if ((uid == null || uid.isEmpty) &&
        uname.isEmpty &&
        memberId.isEmpty &&
        memberName.isEmpty) {
      return true;
    }

    if (reminder.isOpenTask) {
      final creatorMatch = (uid != null && uid.isNotEmpty && _matchesUserId(reminder.creatorId, uid)) ||
          (memberId.isNotEmpty && _matchesUserId(reminder.creatorId, memberId)) ||
          (reminder.creatorName != null &&
              (_matchesUserName(reminder.creatorName!, uname) ||
                  _matchesUserName(reminder.creatorName!, memberName))) ||
          _matchesUserName(reminder.creatorId, uname) ||
          _matchesUserName(reminder.creatorId, memberName);
      return creatorMatch;
    }

    final assigneeMatch = (uid != null && uid.isNotEmpty && _matchesUserId(reminder.assignedTo, uid)) ||
        (memberId.isNotEmpty && _matchesUserId(reminder.assignedTo, memberId)) ||
        (reminder.assignedToName.isNotEmpty &&
            (_matchesUserName(reminder.assignedToName, uname) ||
                _matchesUserName(reminder.assignedToName, memberName))) ||
        _matchesUserName(reminder.assignedTo, uname) ||
        _matchesUserName(reminder.assignedTo, memberName);
    return assigneeMatch;
  }

  /// Khởi động bộ đếm đồng hồ 1 giây toàn cục nếu chưa chạy
  void ensureClockRunning({bool forceRestart = false}) {
    if (forceRestart) {
      _globalClockTimer?.cancel();
      _globalClockTimer = null;
    }
    if (_globalClockTimer != null && _globalClockTimer!.isActive) return;
    _globalClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      try {
        final now = DateTime.now();
        clockTick.value = now;
        if (_trackedReminders.isNotEmpty) {
          _evaluateDueReminders(
            _trackedReminders,
            now: now,
            currentUserId: _lastCurrentUserId,
            currentUserName: _lastCurrentUserName,
            currentUserMemberId: _lastCurrentUserMemberId,
            currentUserFamilyName: _lastCurrentUserFamilyName,
            context: _lastContext,
            onOpenDetail: _lastOnOpenDetail,
          );
        }
      } catch (e) {
        debugPrint('MultiTierEscalationService clock tick error: $e');
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
        _syncOverdueToFirestore(reminder);
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

  /// Đặt lịch nhắc lại thêm đúng 1 lần nữa sau 30 phút khi người dùng bấm "Biết rồi / Bỏ qua"
  void scheduleSnoozeReminder(
    ReminderModel reminder, {
    BuildContext? context,
  }) {
    if (snoozedOnceReminderIds.contains(reminder.id)) return;
    snoozedOnceReminderIds.add(reminder.id);

    _safeSnoozeTimers[reminder.id]?.cancel();
    final targetTime = DateTime.now().add(snoozeDuration);
    snoozeDueAt[reminder.id] = targetTime;

    _safeSnoozeTimers[reminder.id] = Timer(snoozeDuration, () {
      _fireSnoozeFollowUpIfStillPending(reminder.id, fallbackReminder: reminder);
    });

    final ctx = context ?? _lastContext ?? navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      try {
        final mins = snoozeDuration.inMinutes > 0
            ? '${snoozeDuration.inMinutes} phút'
            : '${snoozeDuration.inSeconds} giây';
        final minsEn = snoozeDuration.inMinutes > 0
            ? '${snoozeDuration.inMinutes} minutes'
            : '${snoozeDuration.inSeconds} seconds';
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.text(
                '🔔 Đã tạm ẩn. Sẽ nhắc lại "${reminder.title}" thêm 1 lần nữa sau $mins!',
                '🔔 Snoozed. Will remind "${reminder.title}" 1 more time in $minsEn!',
              ),
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF005F50),
          ),
        );
      } catch (_) {}
    }
  }

  void _fireSnoozeFollowUpIfStillPending(
    String reminderId, {
    ReminderModel? fallbackReminder,
  }) {
    _safeSnoozeTimers.remove(reminderId)?.cancel();
    snoozeDueAt.remove(reminderId);

    final ReminderModel? latest = _trackedReminders
            .where((r) => r.id == reminderId)
            .firstOrNull ??
        fallbackReminder;

    if (latest == null) return;
    if (latest.isCompleted || latest.isDeleted || latest.isSubmitted) return;
    if (!shouldNotifyUser(
      latest,
      currentUserId: _lastCurrentUserId,
      currentUserName: _lastCurrentUserName,
    )) {
      return;
    }

    alertedDueReminderIds.remove(latest.id);
    _safeFollowUpActiveIds.add(latest.id);
    triggerDueAlarmAndPopup(
      latest,
      currentUserId: _lastCurrentUserId,
      currentUserName: _lastCurrentUserName,
      context: _lastContext,
      onOpenDetail: _lastOnOpenDetail,
      isSnoozeFollowUp: true,
    );
  }

  /// Kích hoạt chuông reo báo thức và hiển thị Khung Thông Báo Nổi (Due Alert Dialog)
  void triggerDueAlarmAndPopup(
    ReminderModel reminder, {
    String? currentUserId,
    String? currentUserName,
    String? currentUserMemberId,
    String? currentUserFamilyName,
    BuildContext? context,
    void Function(ReminderModel)? onOpenDetail,
    bool isSnoozeFollowUp = false,
  }) {
    if (currentUserId != null && currentUserId.isNotEmpty) {
      _lastCurrentUserId = currentUserId;
    }
    if (currentUserName != null && currentUserName.isNotEmpty) {
      _lastCurrentUserName = currentUserName;
    }
    if (currentUserMemberId != null && currentUserMemberId.isNotEmpty) {
      _lastCurrentUserMemberId = currentUserMemberId;
    }
    if (currentUserFamilyName != null && currentUserFamilyName.isNotEmpty) {
      _lastCurrentUserFamilyName = currentUserFamilyName;
    }
    if (context != null) _lastContext = context;
    if (onOpenDetail != null) _lastOnOpenDetail = onOpenDetail;

    if (!shouldNotifyUser(
      reminder,
      currentUserId: _lastCurrentUserId,
      currentUserName: _lastCurrentUserName,
      currentUserMemberId: _lastCurrentUserMemberId,
      currentUserFamilyName: _lastCurrentUserFamilyName,
    )) {
      return;
    }

    if (alertedDueReminderIds.contains(reminder.id)) return;
    alertedDueReminderIds.add(reminder.id);
    if (isSnoozeFollowUp) {
      _safeFollowUpActiveIds.add(reminder.id);
    }

    // 1. Kích hoạt chuông reo báo thức (Bell Chime) & rung ngay lập tức
    _currentlyRingingReminderId = reminder.id;
    AlarmSoundService.instance.startAlarm();

    // 2. Bắn thông báo In-app vào Notification Hub cho đúng người nhận
    final bool isUnclaimedOpen = reminder.isOpenTask;
    final String targetUid =
        isUnclaimedOpen ? reminder.creatorId : reminder.assignedTo;

    final String notifTitle = isUnclaimedOpen
        ? (isSnoozeFollowUp
            ? '⏰ Nhắc lại (30p): Việc xung phong "${reminder.title}" chưa ai nhận!'
            : '⏰ Việc xung phong tới hạn: ${reminder.title}!')
        : (isSnoozeFollowUp
            ? '⏰ Nhắc lại (30p): ${reminder.title}!'
            : '⏰ Đến giờ: ${reminder.title}!');

    final String notifTitleEn = isUnclaimedOpen
        ? (isSnoozeFollowUp
            ? '⏰ 30m Follow-up: Volunteer task "${reminder.title}" still unclaimed!'
            : '⏰ Volunteer Task Due: ${reminder.title}!')
        : (isSnoozeFollowUp
            ? '⏰ 30m Follow-up: ${reminder.title}!'
            : '⏰ Task Due: ${reminder.title}!');

    final String notifBody = isUnclaimedOpen
        ? 'Nhiệm vụ xung phong "${reminder.title}" (${reminder.time}) bạn tạo đã đến hạn nhưng chưa có ai nhận làm. Hãy kiểm tra hoặc giao trực tiếp nhé!'
        : (isSnoozeFollowUp
            ? 'Đã qua 30 phút từ lần nhắc trước, nhiệm vụ "${reminder.title}" (${reminder.time}) của bạn vẫn chưa hoàn thành!'
            : 'Nhiệm vụ "${reminder.title}" giao cho bạn đã đến giờ thực hiện (${reminder.time}). Hãy hoàn tất ngay nhé!');

    final String notifBodyEn = isUnclaimedOpen
        ? 'Volunteer task "${reminder.title}" (${reminder.time}) you created is due but nobody has claimed it yet!'
        : (isSnoozeFollowUp
            ? '30 minutes have passed and your task "${reminder.title}" (${reminder.time}) is still not completed!'
            : 'Task "${reminder.title}" assigned to you is due now (${reminder.time}). Please complete it!');

    unawaited(
      NotificationService.instance.addNotification(
        familyId: reminder.familyId,
        targetUserId: targetUid,
        title: notifTitle,
        titleEn: notifTitleEn,
        body: notifBody,
        bodyEn: notifBodyEn,
        type: isSnoozeFollowUp ? 'task_due_snooze_30m' : 'task_due',
      ),
    );

    // 3. Đưa vào hàng đợi hiển thị Khung Thông Báo Nổi sau khi frame render xong
    if (!_safePendingAlertQueue.any((r) => r.id == reminder.id)) {
      _safePendingAlertQueue.add(reminder);
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
    if (DueReminderAlertDialog.isShowing || _safePendingAlertQueue.isEmpty) {
      return;
    }

    BuildContext? targetContext;
    if (_lastContext != null && _lastContext!.mounted) {
      targetContext = _lastContext;
    } else if (navigatorKey.currentState?.overlay?.context != null) {
      targetContext = navigatorKey.currentState!.overlay!.context;
    } else if (navigatorKey.currentContext != null) {
      targetContext = navigatorKey.currentContext;
    }

    if (targetContext == null) {
      return;
    }

    final nextReminder = _safePendingAlertQueue.removeAt(0);
    final isFollowUp = _safeFollowUpActiveIds.contains(nextReminder.id);
    try {
      await DueReminderAlertDialog.show(
        targetContext,
        reminder: nextReminder,
        isSnoozeFollowUp: isFollowUp,
        onOpenDetail: _lastOnOpenDetail,
        onSnoozeDismiss: (rem) {
          scheduleSnoozeReminder(rem, context: targetContext);
        },
      );
    } catch (e) {
      debugPrint('_processNextAlertInQueue show dialog error: $e');
    }

    if (_safePendingAlertQueue.isNotEmpty) {
      _scheduleProcessAlertQueue();
    }
  }

  /// Đồng bộ trạng thái quá hạn lên Firestore thời gian thực để các tab/thiết bị khác nhận WebSocket event
  void _syncOverdueToFirestore(ReminderModel reminder) {
    if (reminder.isCompleted || reminder.isDeleted || reminder.isSubmitted) return;
    if (reminder.status == ReminderStatus.overdue) return;
    if (_safeSyncedOverdueReminderIds.contains(reminder.id)) return;
    _safeSyncedOverdueReminderIds.add(reminder.id);

    // Cập nhật ngay trong bộ nhớ để UI không bị trễ hoặc spam
    final idx = _trackedReminders.indexWhere((r) => r.id == reminder.id);
    if (idx != -1) {
      _trackedReminders[idx] = reminder.copyWith(status: ReminderStatus.overdue);
    }

    if (Firebase.apps.isNotEmpty) {
      try {
        FirebaseFirestore.instance
            .collection('reminders')
            .doc(reminder.id)
            .update({
          'status': ReminderStatus.overdue,
          'isOverdue': true,
        }).then((_) {
          debugPrint('[_syncOverdueToFirestore] Synced overdue status to Firestore for: ${reminder.title} (${reminder.id})');
        }).catchError((e) {
          debugPrint('[_syncOverdueToFirestore] Firestore update error: $e');
        });
      } catch (e) {
        debugPrint('[_syncOverdueToFirestore] Exception: $e');
      }
    }
  }

  /// Quét đồng bộ danh sách lời nhắc để tự động hẹn giờ và kiểm tra nhiệm vụ đến hạn
  void syncReminders(
    List<ReminderModel> reminders, {
    String? currentUserId,
    String? currentUserName,
    String? currentUserMemberId,
    String? currentUserFamilyName,
    BuildContext? context,
    void Function(ReminderModel)? onOpenDetail,
  }) {
    try {
      _trackedReminders = reminders;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        _lastCurrentUserId = currentUserId;
      }
      if (currentUserName != null && currentUserName.isNotEmpty) {
        _lastCurrentUserName = currentUserName;
      }
      if (currentUserMemberId != null && currentUserMemberId.isNotEmpty) {
        _lastCurrentUserMemberId = currentUserMemberId;
      }
      if (currentUserFamilyName != null && currentUserFamilyName.isNotEmpty) {
        _lastCurrentUserFamilyName = currentUserFamilyName;
      }
      if (context != null) _lastContext = context;
      if (onOpenDetail != null) _lastOnOpenDetail = onOpenDetail;

      ensureClockRunning();
      _evaluateDueReminders(
        reminders,
        now: DateTime.now(),
        currentUserId: _lastCurrentUserId,
        currentUserName: _lastCurrentUserName,
        currentUserMemberId: _lastCurrentUserMemberId,
        currentUserFamilyName: _lastCurrentUserFamilyName,
        context: context,
        onOpenDetail: onOpenDetail,
      );
    } catch (e) {
      debugPrint('MultiTierEscalationService syncReminders error: $e');
    }
  }

  void _evaluateDueReminders(
    List<ReminderModel> reminders, {
    required DateTime now,
    String? currentUserId,
    String? currentUserName,
    String? currentUserMemberId,
    String? currentUserFamilyName,
    BuildContext? context,
    void Function(ReminderModel)? onOpenDetail,
  }) {
    final effectiveUserId = _resolveCurrentUserId(currentUserId);
    final effectiveUserName = currentUserName ?? _lastCurrentUserName;
    final effectiveMemberId = currentUserMemberId ?? _lastCurrentUserMemberId;
    final effectiveFamilyName = currentUserFamilyName ?? _lastCurrentUserFamilyName;

    for (final r in reminders) {
      if (r.isCompleted || r.isDeleted || r.isSubmitted) {
        _safePreviouslyPendingIds.remove(r.id);
        cancelEscalation(r.id);
        continue;
      }

      final snoozeTarget = snoozeDueAt[r.id];
      if (snoozeTarget != null && !snoozeTarget.isAfter(now)) {
        _fireSnoozeFollowUpIfStillPending(r.id, fallbackReminder: r);
        continue;
      }

      final dt = r.dueDateTime;
      if (dt == null) continue;

      if (!dt.isAfter(now)) {
        final diff = now.difference(dt);
        final justTransitionedFromPending =
            _safePreviouslyPendingIds.remove(r.id);

        if (justTransitionedFromPending || r.status != ReminderStatus.overdue) {
          _syncOverdueToFirestore(r);
        }

        if (shouldNotifyUser(
          r,
          currentUserId: effectiveUserId,
          currentUserName: effectiveUserName,
          currentUserMemberId: effectiveMemberId,
          currentUserFamilyName: effectiveFamilyName,
        )) {
          if ((justTransitionedFromPending || diff.inMinutes < 15) &&
              !alertedDueReminderIds.contains(r.id)) {
            triggerDueAlarmAndPopup(
              r,
              currentUserId: effectiveUserId,
              currentUserName: effectiveUserName,
              currentUserMemberId: effectiveMemberId,
              currentUserFamilyName: effectiveFamilyName,
              context: context ?? _lastContext,
              onOpenDetail: onOpenDetail ?? _lastOnOpenDetail,
            );
          }
        }
      } else {
        _safePreviouslyPendingIds.add(r.id);
        if (!hasActiveEscalation(r.id)) {
          scheduleMultiTierEscalation(r);
        }
      }
    }
  }

  /// Tự động hủy toàn bộ các mốc hẹn giờ rung khi bấm Complete hoặc Delete
  void cancelEscalation(String reminderId) {
    final timers = _activeTimers.remove(reminderId);
    if (timers != null) {
      for (final t in timers) {
        t.cancel();
      }
    }
    _safeSnoozeTimers.remove(reminderId)?.cancel();
    snoozeDueAt.remove(reminderId);
    _safeFollowUpActiveIds.remove(reminderId);
    _safeSyncedOverdueReminderIds.remove(reminderId);
    _safePendingAlertQueue.removeWhere((r) => r.id == reminderId);
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
    for (final t in _safeSnoozeTimers.values) {
      t.cancel();
    }
    _activeTimers.clear();
    _safeSnoozeTimers.clear();
    snoozeDueAt.clear();
    snoozedOnceReminderIds.clear();
    _safeFollowUpActiveIds.clear();
    alertedDueReminderIds.clear();
    _safeSyncedOverdueReminderIds.clear();
    _safePreviouslyPendingIds.clear();
    _safePendingAlertQueue.clear();
    _currentlyRingingReminderId = null;
    _lastCurrentUserId = null;
    _lastCurrentUserName = null;
    _lastCurrentUserMemberId = null;
    _lastCurrentUserFamilyName = null;
    _trackedReminders = [];
    _globalClockTimer?.cancel();
    _globalClockTimer = null;
    AlarmSoundService.instance.stopAlarm();
  }

  bool hasActiveEscalation(String reminderId) =>
      _activeTimers.containsKey(reminderId);

  bool hasPendingSnooze(String reminderId) =>
      snoozeDueAt.containsKey(reminderId);

  void _triggerTierAlert(ReminderModel reminder, EscalationTier tier) {
    try {
      switch (tier) {
        case EscalationTier.tier1Due:
          triggerDueAlarmAndPopup(
            reminder,
            currentUserId: _lastCurrentUserId,
            currentUserName: _lastCurrentUserName,
            currentUserMemberId: _lastCurrentUserMemberId,
            currentUserFamilyName: _lastCurrentUserFamilyName,
          );
          break;

        case EscalationTier.tier2SixHours:
          if (!shouldNotifyUser(
            reminder,
            currentUserId: _lastCurrentUserId,
            currentUserName: _lastCurrentUserName,
            currentUserMemberId: _lastCurrentUserMemberId,
            currentUserFamilyName: _lastCurrentUserFamilyName,
          )) {
            break;
          }
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 250), () {
            try {
              HapticFeedback.heavyImpact();
            } catch (_) {}
          });
          unawaited(
            NotificationService.instance.addNotification(
              familyId: reminder.familyId,
              targetUserId:
                  reminder.isOpenTask ? reminder.creatorId : reminder.assignedTo,
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
          HapticFeedback.vibrate();
          Future.delayed(const Duration(milliseconds: 300), () {
            try {
              HapticFeedback.vibrate();
            } catch (_) {}
          });
          unawaited(
            NotificationService.instance.addNotification(
              familyId: reminder.familyId,
              targetUserId: reminder.creatorId,
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
        _emitDemoTier(reminder, EscalationTier.tier2SixHours, 5);
      } else if (elapsed == 10) {
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

  void stopDemo() {
    _demoTimer?.cancel();
    _demoTimer = null;
    _demoAlertController?.close();
    _demoAlertController = null;
  }

  int get activeEscalationCount => _activeTimers.length;
}
