import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dịch vụ phát âm thanh chuông reo báo thức & rung phản hồi khi Lời nhắc đến hạn
class AlarmSoundService {
  static final AlarmSoundService instance = AlarmSoundService._();
  AlarmSoundService._();

  bool disableAudioPlayerForTest = false;
  AudioPlayer? _player;
  Timer? _ringTimer;
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  AudioPlayer? _getAudioPlayer() {
    if (disableAudioPlayerForTest) return null;
    if (_player == null) {
      try {
        _player = AudioPlayer();
      } catch (e) {
        debugPrint('AudioPlayer init error (e.g. in test env): $e');
      }
    }
    return _player;
  }

  /// Bắt đầu phát chuông reo (lặp lại định kỳ mỗi 1.2s, tối đa [maxRings] lần hoặc tới khi stop)
  Future<void> startAlarm({int maxRings = 6}) async {
    stopAlarm();
    _isPlaying = true;
    int ringCount = 0;

    _playSingleRing();
    ringCount++;

    _ringTimer = Timer.periodic(const Duration(milliseconds: 1300), (timer) {
      if (!_isPlaying || ringCount >= maxRings) {
        stopAlarm();
        return;
      }
      _playSingleRing();
      ringCount++;
    });
  }

  void _playSingleRing() {
    // 1. Rung máy điện thoại vật lý
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    // 2. Phát âm thanh chuông cảnh báo hệ thống (hoạt động tốt trên mọi nền tảng Web, Android, iOS, Windows)
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    // 3. Kết hợp AudioPlayer phát file âm thanh mẫu nếu khả dụng
    final player = _getAudioPlayer();
    if (player != null) {
      try {
        player.play(AssetSource('audio/sample_voice_reminder.wav')).catchError((_) {});
      } catch (e) {
        debugPrint('AlarmSoundService audio player error (safely handled): $e');
      }
    }
  }

  /// Tắt chuông reo và dừng rung ngay lập tức
  void stopAlarm() {
    _isPlaying = false;
    _ringTimer?.cancel();
    _ringTimer = null;
    if (!disableAudioPlayerForTest && _player != null) {
      try {
        _player?.stop().catchError((_) {});
      } catch (_) {}
    }
  }
}
