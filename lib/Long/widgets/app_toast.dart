import 'package:flutter/material.dart';

/// Lightweight, auto-dismissing Toast displayed at the TOP of the screen.
/// Used for quick confirmations like "Đã sao chép", "Đã lưu thay đổi", etc.
class AppToast {
  static OverlayEntry? _activeEntry;

  /// Hiển thị thông báo nhỏ gọn ở phía trên màn hình (Top Toast).
  /// Tự động biến mất sau [duration] (mặc định 2.2 giây) mà không cần người dùng thao tác.
  static void show(
    BuildContext context,
    String message, {
    bool isSuccess = true,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    // Hủy bỏ toast cũ đang hiển thị nếu có
    _activeEntry?.remove();
    _activeEntry = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _AppToastWidget(
        message: message,
        isSuccess: isSuccess,
        icon: icon,
        duration: duration,
        onDismiss: () {
          if (_activeEntry == entry) {
            entry.remove();
            _activeEntry = null;
          }
        },
      ),
    );

    _activeEntry = entry;
    overlayState.insert(entry);
  }

  /// Helper hiển thị thông báo thành công
  static void showSuccess(BuildContext context, String message) {
    show(context, message, isSuccess: true, icon: Icons.check_circle_rounded);
  }

  /// Helper hiển thị thông tin / thông báo nhanh
  static void showInfo(BuildContext context, String message) {
    show(context, message, isSuccess: false, icon: Icons.info_outline_rounded);
  }
}

class _AppToastWidget extends StatefulWidget {
  final String message;
  final bool isSuccess;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismiss;

  const _AppToastWidget({
    required this.message,
    required this.isSuccess,
    this.icon,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_AppToastWidget> createState() => _AppToastWidgetState();
}

class _AppToastWidgetState extends State<_AppToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();

    // Tự động đóng toast sau khoảng thời gian duration
    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) {
            widget.onDismiss();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: topPadding + 10,
      left: 16,
      right: 16,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.isSuccess
                      ? const Color(0xFF005F50)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon ??
                          (widget.isSuccess
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded),
                      color: Colors.white,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
