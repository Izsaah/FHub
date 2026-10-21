import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/reminder_model.dart';
import '../services/reminder_repository.dart';

/// Hộp thoại mô phỏng cơ chế Nhắc lịch Đa tầng (Demo 10 Giây)
/// Rút gọn chu trình 12 tiếng thực tế (0h -> +6h -> +12h) thành 10 giây (0s -> 5s -> 10s).
class MultiTierSimulationDialog extends StatefulWidget {
  final ReminderModel reminder;
  final ReminderRepository? repository;
  final String? currentUserId;
  final VoidCallback? onReminderCompleted;

  const MultiTierSimulationDialog({
    super.key,
    required this.reminder,
    this.repository,
    this.currentUserId,
    this.onReminderCompleted,
  });

  static Future<void> show(
    BuildContext context, {
    required ReminderModel reminder,
    ReminderRepository? repository,
    String? currentUserId,
    VoidCallback? onReminderCompleted,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => MultiTierSimulationDialog(
        reminder: reminder,
        repository: repository,
        currentUserId: currentUserId,
        onReminderCompleted: onReminderCompleted,
      ),
    );
  }

  @override
  State<MultiTierSimulationDialog> createState() =>
      _MultiTierSimulationDialogState();
}

class _MultiTierSimulationDialogState extends State<MultiTierSimulationDialog>
    with SingleTickerProviderStateMixin {
  late final MultiTierEscalationService _service;
  StreamSubscription<EscalationAlert>? _alertSub;
  Timer? _countdownTimer;

  int _secondsElapsed = 0;
  bool _isCompletedEarly = false;
  bool _isDemoRunning = false;
  final List<EscalationAlert> _receivedAlerts = [];
  EscalationTier? _currentActiveTier;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _service = MultiTierEscalationService.instance;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startSimulation();
  }

  void _startSimulation() {
    _service.stopDemo();
    _countdownTimer?.cancel();
    _alertSub?.cancel();

    setState(() {
      _secondsElapsed = 0;
      _isCompletedEarly = false;
      _isDemoRunning = true;
      _receivedAlerts.clear();
      _currentActiveTier = EscalationTier.tier1Due;
    });

    final stream = _service.start10SecondDemo(widget.reminder);
    _alertSub = stream.listen((alert) {
      if (!mounted) return;
      setState(() {
        _receivedAlerts.add(alert);
        _currentActiveTier = alert.tier;
      });
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsElapsed < 10) {
          _secondsElapsed++;
        } else {
          _isDemoRunning = false;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleCompleteEarly() async {
    _service.stopDemo();
    _service.cancelEscalation(widget.reminder.id);
    _countdownTimer?.cancel();

    setState(() {
      _isCompletedEarly = true;
      _isDemoRunning = false;
    });

    try {
      HapticFeedback.lightImpact();
      if (widget.repository != null && widget.currentUserId != null) {
        await widget.repository!.completeReminder(
          reminderId: widget.reminder.id,
          currentUserId: widget.currentUserId!,
        );
      }
      widget.onReminderCompleted?.call();
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '🎉 Hoàn thành xuất sắc! Đã hủy toàn bộ các mốc hẹn rung và báo động khẩn.',
        ),
        backgroundColor: Color(0xFF0D7A68),
      ),
    );
  }

  void _stopAndClose() {
    _service.stopDemo();
    _countdownTimer?.cancel();
    _alertSub?.cancel();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _service.stopDemo();
    _countdownTimer?.cancel();
    _alertSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    final progress = (_secondsElapsed / 10.0).clamp(0.0, 1.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2EC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.science_rounded,
                      color: primaryColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mô phỏng Nhắc lịch Đa tầng',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF151D1B),
                          ),
                        ),
                        Text(
                          'Chu trình 12 giờ rút gọn trong 10 giây',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6E7A75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    onPressed: _stopAndClose,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Thông tin nhắc việc đang chạy demo
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2EBE7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.task_alt_rounded,
                            size: 16, color: primaryColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.reminder.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF151D1B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Người nhận: ${widget.reminder.assignedToName}  •  Người giao: ${widget.reminder.creatorName ?? "Bố Mẹ"}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6E7A75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Đồng hồ đo tiến độ 10s
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isCompletedEarly
                        ? [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)]
                        : _currentActiveTier == EscalationTier.tier3TwelveHours
                            ? [const Color(0xFFFFEBEE), const Color(0xFFFFCDD2)]
                            : _currentActiveTier == EscalationTier.tier2SixHours
                                ? [
                                    const Color(0xFFFFF3E0),
                                    const Color(0xFFFFE0B2)
                                  ]
                                : [
                                    const Color(0xFFE0F2EC),
                                    const Color(0xFFB2DFDB)
                                  ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ScaleTransition(
                          scale: _isDemoRunning
                              ? _pulseAnimation
                              : const AlwaysStoppedAnimation(1.0),
                          child: Icon(
                            _isCompletedEarly
                                ? Icons.check_circle_rounded
                                : _currentActiveTier ==
                                        EscalationTier.tier3TwelveHours
                                    ? Icons.crisis_alert_rounded
                                    : _currentActiveTier ==
                                            EscalationTier.tier2SixHours
                                        ? Icons.warning_amber_rounded
                                        : Icons.notifications_active_rounded,
                            color: _isCompletedEarly
                                ? primaryColor
                                : _currentActiveTier ==
                                        EscalationTier.tier3TwelveHours
                                    ? const Color(0xFFC62828)
                                    : _currentActiveTier ==
                                            EscalationTier.tier2SixHours
                                        ? const Color(0xFFEF6C00)
                                        : primaryColor,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isCompletedEarly
                                ? 'Đã ngắt chu trình (Hoàn thành)'
                                : _currentActiveTier ==
                                        EscalationTier.tier3TwelveHours
                                    ? '🚨 Đang Rung Báo Động Khẩn Cấp!'
                                    : _currentActiveTier ==
                                            EscalationTier.tier2SixHours
                                        ? '⚠️ Đang Rung Dồn Dập Lần 1!'
                                        : '🔔 Đang Nhắc Nhẹ Đúng Hạn',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _isCompletedEarly
                                  ? primaryColor
                                  : _currentActiveTier ==
                                          EscalationTier.tier3TwelveHours
                                      ? const Color(0xFFC62828)
                                      : _currentActiveTier ==
                                              EscalationTier.tier2SixHours
                                          ? const Color(0xFFEF6C00)
                                          : primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_secondsElapsed}s / 10s',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF151D1B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.6),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _currentActiveTier == EscalationTier.tier3TwelveHours
                              ? const Color(0xFFC62828)
                              : _currentActiveTier ==
                                      EscalationTier.tier2SixHours
                                  ? const Color(0xFFEF6C00)
                                  : primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Timeline 3 mốc (0s / 5s / 10s)
              const Text(
                'Lộ trình thang bậc cảnh báo:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF151D1B),
                ),
              ),
              const SizedBox(height: 10),
              _buildTimelineStep(
                title: 'Mốc 1 (0s ↔ Đúng giờ hẹn 0h)',
                description: 'Nhắc nhẹ nhàng (âm báo chuẩn + rung nhẹ 1 nhịp)',
                icon: Icons.notifications_none_rounded,
                isReached: _secondsElapsed >= 0,
                color: const Color(0xFF0D7A68),
              ),
              const SizedBox(height: 8),
              _buildTimelineStep(
                title: 'Mốc 2 (5s ↔ Trễ hạn +6 tiếng)',
                description:
                    'Nhắc Rung lần 1 (2 nhịp dồn dập trên máy người nhận)',
                icon: Icons.vibration_rounded,
                isReached: _secondsElapsed >= 5,
                color: const Color(0xFFEF6C00),
              ),
              const SizedBox(height: 8),
              _buildTimelineStep(
                title: 'Mốc 3 (10s ↔ Trễ hạn +12 tiếng)',
                description:
                    'Rung khẩn cấp lần 2 VÀ gửi cảnh báo báo động về máy Bố/Mẹ!',
                icon: Icons.emergency_share_rounded,
                isReached: _secondsElapsed >= 10,
                color: const Color(0xFFC62828),
              ),
              const SizedBox(height: 16),

              // Nhật ký thông điệp phát ra gần nhất
              if (_receivedAlerts.isNotEmpty) ...[
                const Text(
                  'Thông điệp phát ra gần nhất:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF151D1B),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F6F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2EBE7)),
                  ),
                  child: Text(
                    _receivedAlerts.last.message,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF151D1B),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Các nút hành động
              if (!_isCompletedEarly)
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text(
                      '✓ Hoàn thành ngay (Dừng rung)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _handleCompleteEarly,
                  ),
                ),
              if (_isCompletedEarly)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2EC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: primaryColor, size: 20),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Đã hủy toàn bộ cảnh báo rung!',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF151D1B),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Chạy lại'),
                      onPressed: _startSimulation,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _stopAndClose,
                      child: const Text('Đóng'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineStep({
    required String title,
    required String description,
    required IconData icon,
    required bool isReached,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isReached ? color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isReached ? color.withValues(alpha: 0.3) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: isReached ? color : Colors.grey.shade400,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isReached ? color : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isReached
                        ? const Color(0xFF2C3E37)
                        : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          if (isReached)
            Icon(Icons.check_rounded, size: 16, color: color)
          else
            Icon(Icons.hourglass_empty_rounded,
                size: 14, color: Colors.grey.shade400),
        ],
      ),
    );
  }
}
