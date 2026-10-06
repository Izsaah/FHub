import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/voice_audio_service.dart';

class VoiceRecorderWidget extends StatefulWidget {
  final Function(String path, int durationSeconds, String description) onVoiceRecorded;
  final VoidCallback onVoiceRemoved;
  final String? initialAudioPath;
  final int? initialDuration;
  final String? initialDescription;

  const VoiceRecorderWidget({
    super.key,
    required this.onVoiceRecorded,
    required this.onVoiceRemoved,
    this.initialAudioPath,
    this.initialDuration,
    this.initialDescription,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget>
    with SingleTickerProviderStateMixin {
  final _audioService = VoiceAudioService();
  final _descriptionController = TextEditingController();

  VoiceRecordState _recordState = VoiceRecordState.idle;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _recordedPath;

  bool _isPreviewPlaying = false;
  int _previewPositionSec = 0;
  Timer? _previewTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Real-time microphone audio input visualizer
  StreamSubscription? _amplitudeSub;
  Timer? _waveTickTimer;
  double _soundLevel = 0.2;
  double _currentDb = -45.0;
  bool _isSoundDetected = false;
  int _waveTick = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.initialAudioPath != null && widget.initialAudioPath!.isNotEmpty) {
      _recordedPath = widget.initialAudioPath;
      _recordSeconds = widget.initialDuration ?? 10;
      _descriptionController.text = widget.initialDescription ?? '';
      _recordState = VoiceRecordState.recorded;
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _previewTimer?.cancel();
    _amplitudeSub?.cancel();
    _waveTickTimer?.cancel();
    _pulseController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startRecording() async {
    try {
      final path = await _audioService.startRecording();
      _recordedPath = path;

      setState(() {
        _recordState = VoiceRecordState.recording;
        _recordSeconds = 0;
        _soundLevel = 0.25;
        _isSoundDetected = false;
      });

      _pulseController.repeat(reverse: true);

      // 1. Seconds counter timer (max 30s)
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          _recordSeconds++;
        });
        if (_recordSeconds >= 30) {
          _stopRecording();
        }
      });

      // 2. Real-time microphone amplitude listener
      _amplitudeSub?.cancel();
      _amplitudeSub = _audioService
          .onAmplitudeChanged(interval: const Duration(milliseconds: 70))
          .listen((amp) {
        if (!mounted) return;
        final db = amp.current;
        final norm = ((db + 50.0) / 45.0).clamp(0.1, 1.0);
        setState(() {
          _currentDb = db;
          _soundLevel = norm;
          _isSoundDetected = db > -38.0;
        });
      });

      // 3. Alive visual wave oscillation timer (keeps visualizer lively)
      _waveTickTimer?.cancel();
      _waveTickTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
        if (!mounted || _recordState != VoiceRecordState.recording) {
          timer.cancel();
          return;
        }
        setState(() {
          _waveTick++;
          if (!_isSoundDetected && _soundLevel < 0.25) {
            final sine = (math.sin(_waveTick * 0.35) + 1.0) * 0.5;
            _soundLevel = 0.15 + (sine * 0.2);
          }
        });
      });
    } catch (e) {
      debugPrint('VoiceRecorderWidget: _startRecording failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Không thể bắt đầu ghi âm: ${e.toString().replaceAll('Exception: ', '')}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            backgroundColor: const Color(0xFFBA1A1A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _waveTickTimer?.cancel();
    _pulseController.stop();

    final finalPath = await _audioService.stopRecording();
    final actualPath = finalPath ?? _recordedPath ?? 'assets/audio/sample_voice_reminder.wav';

    if (!mounted) return;
    setState(() {
      _recordedPath = actualPath;
      _recordState = VoiceRecordState.recorded;
      if (_recordSeconds == 0) _recordSeconds = 3;
    });

    _notifyChange();
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _waveTickTimer?.cancel();
    _pulseController.stop();
    await _audioService.cancelRecording();

    if (!mounted) return;
    setState(() {
      _recordState = VoiceRecordState.idle;
      _recordSeconds = 0;
      _recordedPath = null;
    });
  }

  void _removeRecording() {
    _previewTimer?.cancel();
    _audioService.stopAudio();

    setState(() {
      _recordState = VoiceRecordState.idle;
      _recordSeconds = 0;
      _recordedPath = null;
      _isPreviewPlaying = false;
      _previewPositionSec = 0;
      _descriptionController.clear();
    });

    widget.onVoiceRemoved();
  }

  void _togglePreviewPlay() {
    if (_recordedPath == null) return;

    if (_isPreviewPlaying) {
      _previewTimer?.cancel();
      _audioService.pauseAudio();
      setState(() => _isPreviewPlaying = false);
    } else {
      setState(() {
        _isPreviewPlaying = true;
        if (_previewPositionSec >= _recordSeconds) {
          _previewPositionSec = 0;
        }
      });

      _audioService.playAudio(
        reminderId: 'preview_id',
        audioPath: _recordedPath!,
      );

      _previewTimer?.cancel();
      _previewTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _previewPositionSec++;
          if (_previewPositionSec >= _recordSeconds) {
            timer.cancel();
            _isPreviewPlaying = false;
            _previewPositionSec = 0;
          }
        });
      });
    }
  }

  void _notifyChange() {
    if (_recordedPath != null) {
      widget.onVoiceRecorded(
        _recordedPath!,
        _recordSeconds,
        _descriptionController.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _recordState == VoiceRecordState.recording
              ? const Color(0xFFBA1A1A)
              : const Color(0xFFBDC9C4),
          width: _recordState == VoiceRecordState.recording ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.mic_rounded,
                    color: _recordState == VoiceRecordState.recording
                        ? const Color(0xFFBA1A1A)
                        : primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Ghi âm giọng nói (Micro)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF151D1B),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F5F2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Micro & Loa 🎙️🔊',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Body based on state
          if (_recordState == VoiceRecordState.idle) ...[
            _buildIdleView(primaryColor),
          ] else if (_recordState == VoiceRecordState.recording) ...[
            _buildRecordingView(),
          ] else ...[
            _buildRecordedView(primaryColor),
          ],
        ],
      ),
    );
  }

  Widget _buildIdleView(Color primaryColor) {
    return Column(
      children: [
        Center(
          child: GestureDetector(
            onTap: _startRecording,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F5F2),
                shape: BoxShape.circle,
                border: Border.all(color: primaryColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.mic,
                color: primaryColor,
                size: 32,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Chạm để bắt đầu ghi âm bằng Micro (tối đa 30s)',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF6E7A75),
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRecordingView() {
    final activeColor = _isSoundDetected
        ? const Color(0xFF0D7A68)
        : const Color(0xFFBA1A1A);

    return Column(
      children: [
        // 1. Concentric Ripple Pulse around Mic Button
        SizedBox(
          height: 100,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer expanding ripple reacting to sound amplitude
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: (76 + (_soundLevel * 24)).clamp(76.0, 100.0),
                  height: (76 + (_soundLevel * 24)).clamp(76.0, 100.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeColor.withValues(alpha: 0.12),
                  ),
                ),
                // Inner expanding ripple
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: (66 + (_soundLevel * 14)).clamp(66.0, 85.0),
                  height: (66 + (_soundLevel * 14)).clamp(66.0, 85.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeColor.withValues(alpha: 0.22),
                  ),
                ),
                // Center Mic Button with scale animation
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: activeColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mic,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),

        // 2. Sound Detection Badge (shows whether voice is being picked up)
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _isSoundDetected
                ? const Color(0xFFE0F5EE)
                : const Color(0xFFFFDAD6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: activeColor,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: activeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isSoundDetected
                    ? '🟢 Đang nhận giọng nói: ${_currentDb > -100 ? '${_currentDb.toStringAsFixed(1)} dB' : ''} 🎙️'
                    : '🎙️ Đang lắng nghe âm thanh Micro... (Hãy nói)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: activeColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. Dynamic Live Audio Waveform (22 jumping frequency bars)
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(22, (i) {
              final centerDist = ((i - 10.5).abs() / 11.0);
              final curve = math.cos(centerDist * math.pi * 0.5);
              final dynamicHeight =
                  (8.0 + (_soundLevel * 32.0 * curve)).clamp(6.0, 42.0);

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  height: dynamicHeight,
                  decoration: BoxDecoration(
                    color: _isSoundDetected
                        ? (i % 2 == 0
                            ? const Color(0xFF0D7A68)
                            : const Color(0xFF1CB098))
                        : (i % 2 == 0
                            ? const Color(0xFFBA1A1A)
                            : const Color(0xFFFF5449)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),

        // 4. Timer & Progress Bar (Max 30s)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Thời lượng: ${_formatTime(_recordSeconds)} / 00:30',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: activeColor,
                    ),
                  ),
                  Text(
                    'Còn lại ${30 - _recordSeconds}s',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6E7A75),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_recordSeconds / 30).clamp(0.0, 1.0),
                  backgroundColor: const Color(0xFFE2EAE7),
                  valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 5. Action Buttons (Hủy & Xong/Lưu)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Hủy bản thu'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFBA1A1A),
                side: const BorderSide(color: Color(0xFFBA1A1A)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _cancelRecording,
            ),
            const SizedBox(width: 14),
            FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: const Text('Xong & Nghe lại'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D7A68),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _stopRecording,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecordedView(Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Audio preview bar (Speaker)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF5F1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBCE0D7)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  _isPreviewPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  size: 36,
                  color: primaryColor,
                ),
                onPressed: _togglePreviewPlay,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isPreviewPlaying
                          ? 'Đang phát qua Loa: ${_formatTime(_previewPositionSec)} / ${_formatTime(_recordSeconds)}'
                          : 'Đã ghi âm: ${_formatTime(_recordSeconds)}s',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D7A68),
                      ),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: _recordSeconds > 0
                          ? (_previewPositionSec / _recordSeconds).clamp(0.0, 1.0)
                          : 0.0,
                      backgroundColor: const Color(0xFFBDC9C4),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0D7A68)),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20, color: Color(0xFF6E7A75)),
                tooltip: 'Ghi âm lại',
                onPressed: _startRecording,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFBA1A1A)),
                tooltip: 'Xóa ghi âm',
                onPressed: _removeRecording,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Text field for voice note summary ("ghi chú nó nói về gì")
        const Text(
          'Ghi chú nội dung lời nói *',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF151D1B),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _descriptionController,
          decoration: InputDecoration(
            hintText: 'Nhập tóm tắt (vd: Nhắc uống thuốc lúc 7h tối...)',
            hintStyle: const TextStyle(color: Color(0xFF8E9B95), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF9FDFB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFBDC9C4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFBDC9C4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF0D7A68), width: 1.5),
            ),
          ),
          onChanged: (val) => _notifyChange(),
        ),
      ],
    );
  }
}
