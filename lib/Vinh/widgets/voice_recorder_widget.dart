import 'dart:async';
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
    setState(() {
      _recordState = VoiceRecordState.recording;
      _recordSeconds = 0;
    });

    _pulseController.repeat(reverse: true);
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _recordSeconds++;
      });
      if (_recordSeconds >= 120) {
        // Max 2 minutes
        _stopRecording();
      }
    });

    final path = await _audioService.startRecording();
    _recordedPath = path;
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    _pulseController.stop();

    final finalPath = await _audioService.stopRecording();
    final actualPath = finalPath ?? _recordedPath ?? 'sample_voice_note.m4a';

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
          'Chạm để bắt đầu ghi âm lời nhắc bằng Micro',
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
    return Column(
      children: [
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFFFDAD6),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFBA1A1A), width: 2.5),
            ),
            child: const Icon(
              Icons.mic,
              color: Color(0xFFBA1A1A),
              size: 34,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFBA1A1A),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Đang ghi âm... ${_formatTime(_recordSeconds)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFFBA1A1A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Hủy'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFBA1A1A),
                side: const BorderSide(color: Color(0xFFBA1A1A)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _cancelRecording,
            ),
            const SizedBox(width: 14),
            FilledButton.icon(
              icon: const Icon(Icons.stop, size: 20),
              label: const Text('Xong & Lưu'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D7A68),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
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
