import 'dart:async';
import 'package:flutter/material.dart';
import '../models/reminder_model.dart';
import '../services/voice_audio_service.dart';

class VoiceReminderPlayer extends StatefulWidget {
  final ReminderModel reminder;
  final bool isCompact;

  const VoiceReminderPlayer({
    super.key,
    required this.reminder,
    this.isCompact = true,
  });

  @override
  State<VoiceReminderPlayer> createState() => _VoiceReminderPlayerState();
}

class _VoiceReminderPlayerState extends State<VoiceReminderPlayer>
    with SingleTickerProviderStateMixin {
  final _audioService = VoiceAudioService();
  StreamSubscription? _subscription;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    final totalSec = widget.reminder.voiceDurationSeconds ?? 10;
    _duration = Duration(seconds: totalSec > 0 ? totalSec : 10);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _subscription = _audioService.playbackStateStream.listen((state) {
      if (state['id'] == widget.reminder.id) {
        if (!mounted) return;
        setState(() {
          _isPlaying = state['isPlaying'] == true;
          if (state['position'] is Duration) {
            _position = state['position'] as Duration;
          }
          if (state['duration'] is Duration) {
            _duration = state['duration'] as Duration;
          }
          if (state['isCompleted'] == true) {
            _isPlaying = false;
            _position = Duration.zero;
          }
        });

        if (_isPlaying) {
          if (!_animController.isAnimating) {
            _animController.repeat(reverse: true);
          }
        } else {
          _animController.stop();
        }
      } else if (_isPlaying) {
        // Another audio started playing
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
          _animController.stop();
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _animController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _togglePlay() async {
    final audioPath = widget.reminder.voiceNotePath;
    if (audioPath == null || audioPath.isEmpty) return;

    if (_isPlaying) {
      await _audioService.pauseAudio();
    } else {
      await _audioService.playAudio(
        reminderId: widget.reminder.id,
        audioPath: audioPath,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0D7A68);
    final totalSeconds = _duration.inSeconds > 0 ? _duration.inSeconds : 1;
    final currentSeconds = _position.inSeconds.clamp(0, totalSeconds);
    final progress = currentSeconds / totalSeconds;

    final noteDescription = widget.reminder.voiceNoteDescription;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBCE0D7), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Audio bar: Play button + Waveform/Progress + Time + Loa Badge
          Row(
            children: [
              // Play/Pause circular button
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Progress bar & Waveform simulation
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dynamic waveform bars
                    AnimatedBuilder(
                      animation: _animController,
                      builder: (context, child) {
                        return Row(
                          children: List.generate(18, (index) {
                            final factor = (index % 5 + 1) * 3.0;
                            final animValue = _isPlaying
                                ? (_animController.value * factor)
                                : factor;
                            final height = (6.0 + animValue).clamp(4.0, 22.0);
                            final isPassed = (index / 18) <= progress;

                            return Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                height: height,
                                decoration: BoxDecoration(
                                  color: isPassed
                                      ? primaryColor
                                      : primaryColor.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                    const SizedBox(height: 4),

                    // Duration display
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isPlaying
                              ? _formatDuration(_position)
                              : _formatDuration(_duration),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.volume_up_rounded,
                              size: 13,
                              color: Color(0xFF4C756B),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _isPlaying ? 'Đang phát qua Loa 🔊' : 'Loa máy 🔊',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF4C756B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 2. Voice Note description / summary ("phải có ghi chú nó nói về gì")
          if (noteDescription != null && noteDescription.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFCFE5DE),
                  width: 0.8,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 14,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ghi chú: $noteDescription',
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF2C403B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
