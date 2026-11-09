import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dịch vụ phát âm thanh chuông reo báo thức (Bell Chime) & rung phản hồi khi Lời nhắc đến hạn
class AlarmSoundService {
  static final AlarmSoundService instance = AlarmSoundService._();
  AlarmSoundService._();

  bool disableAudioPlayerForTest = false;
  AudioPlayer? _player;
  Timer? _ringTimer;
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Uint8List? _cachedBellWavBytes;

  /// Tạo dữ liệu âm thanh WAV chuẩn (44.1kHz, 16-bit PCM Mono) mô phỏng tiếng Chuông Báo Thức ("Reng - Reng / Ding - Dong")
  /// Giúp phát chuông reo rõ ràng 100% trên cả Chrome Web, Android, iOS, Windows mà không phụ thuộc file ngoài.
  Uint8List _getBellChimeWavBytes() {
    if (_cachedBellWavBytes != null) return _cachedBellWavBytes!;

    const int sampleRate = 44100;
    const double durationSeconds = 0.85;
    final int numSamples = (sampleRate * durationSeconds).toInt();
    final int dataSize = numSamples * 2; // 16-bit mono = 2 bytes/sample
    final int fileSize = 36 + dataSize;

    final ByteData buffer = ByteData(44 + dataSize);

    // RIFF header
    buffer.setUint8(0, 0x52); // 'R'
    buffer.setUint8(1, 0x49); // 'I'
    buffer.setUint8(2, 0x46); // 'F'
    buffer.setUint8(3, 0x46); // 'F'
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint8(8, 0x57); // 'W'
    buffer.setUint8(9, 0x41); // 'A'
    buffer.setUint8(10, 0x56); // 'V'
    buffer.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    buffer.setUint8(12, 0x66); // 'f'
    buffer.setUint8(13, 0x6D); // 'm'
    buffer.setUint8(14, 0x74); // 't'
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    buffer.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    buffer.setUint16(22, 1, Endian.little); // NumChannels (1 = mono)
    buffer.setUint32(24, sampleRate, Endian.little); // SampleRate
    buffer.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    buffer.setUint16(32, 2, Endian.little); // BlockAlign
    buffer.setUint16(34, 16, Endian.little); // BitsPerSample

    // data subchunk
    buffer.setUint8(36, 0x64); // 'd'
    buffer.setUint8(37, 0x61); // 'a'
    buffer.setUint8(38, 0x74); // 't'
    buffer.setUint8(39, 0x61); // 'a'
    buffer.setUint32(40, dataSize, Endian.little);

    // Tổng hợp 2 nhịp chuông ngân (Strike 1: 0.0s -> 0.4s ở 880Hz/1760Hz, Strike 2: 0.4s -> 0.85s ở 1046.5Hz/2093Hz)
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      double sample = 0.0;

      if (t < 0.40) {
        final double localT = t;
        final double env = math.exp(-localT * 8.0);
        // Trộn âm cơ bản A5 (880Hz) + họa âm chuông (1760Hz, 2640Hz) kèm rung nhẹ
        sample = env *
            (0.60 * math.sin(2 * math.pi * 880.0 * localT) +
                0.28 * math.sin(2 * math.pi * 1760.0 * localT) +
                0.12 * math.sin(2 * math.pi * 2640.0 * localT));
      } else {
        final double localT = t - 0.40;
        final double env = math.exp(-localT * 6.5);
        // Nhịp 2 cao và ngân vang C6 (1046.5Hz) + họa âm (2093Hz, 3139.5Hz)
        sample = env *
            (0.60 * math.sin(2 * math.pi * 1046.5 * localT) +
                0.28 * math.sin(2 * math.pi * 2093.0 * localT) +
                0.12 * math.sin(2 * math.pi * 3139.5 * localT));
      }

      final int pcmValue = (sample * 28000).clamp(-32767, 32767).toInt();
      buffer.setInt16(44 + i * 2, pcmValue, Endian.little);
    }

    _cachedBellWavBytes = buffer.buffer.asUint8List();
    return _cachedBellWavBytes!;
  }

  AudioPlayer? _getAudioPlayer() {
    if (disableAudioPlayerForTest) return null;
    if (_player == null) {
      try {
        final p = AudioPlayer();
        p.eventStream.listen(
          (_) {},
          onError: (e) {
            debugPrint('AudioPlayer eventStream handled: $e');
          },
          cancelOnError: false,
        );
        _player = p;
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

    _ringTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (!_isPlaying || ringCount >= maxRings) {
        stopAlarm();
        return;
      }
      _playSingleRing();
      ringCount++;
    });
  }

  void _playSingleRing() {
    // 1. Rung máy điện thoại vật lý & âm báo hệ thống (trên thiết bị di động)
    if (!kIsWeb) {
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }

    // 3. Phát tiếng chuông reo tổng hợp WAV (chạy mượt trên Web Chrome, Android, iOS, Windows)
    final player = _getAudioPlayer();
    if (player != null) {
      try {
        final wavBytes = _getBellChimeWavBytes();
        player.play(BytesSource(wavBytes, mimeType: 'audio/wav')).catchError((e) {
          debugPrint('AlarmSoundService audio player error (safely handled): $e');
        });
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
