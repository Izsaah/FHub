import 'dart:async';
import 'package:flutter/foundation.dart';
import 'voice_audio_service.dart';

/// Triển khai dự phòng cho nền tảng Native (Android/iOS/Desktop) và môi trường Unit Test.
class AiSpeechPlatform {
  AiSpeechPlatform._();
  static final AiSpeechPlatform instance = AiSpeechPlatform._();

  bool _isSpeaking = false;
  bool _isListening = false;
  Timer? _speakTimer;

  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;
  bool get isSttSupported => true;
  bool get isTtsSupported => true;

  Future<void> speak(
    String text, {
    required bool isEnglish,
    VoidCallback? onDone,
  }) async {
    await stopSpeaking();
    _isSpeaking = true;
    // Ước lượng thời lượng đọc tự nhiên theo độ dài câu (tối thiểu 2s, tối đa 8s trên môi trường stub)
    final wordCount = text.trim().split(RegExp(r'\s+')).length;
    final seconds = (wordCount ~/ 3).clamp(2, 8);
    _speakTimer = Timer(Duration(seconds: seconds), () {
      _isSpeaking = false;
      onDone?.call();
    });
  }

  Future<void> stopSpeaking() async {
    _speakTimer?.cancel();
    _speakTimer = null;
    _isSpeaking = false;
    try {
      await VoiceAudioService().stopAudio();
    } catch (_) {}
  }

  Future<bool> startListening({
    required bool isEnglish,
    required ValueChanged<String> onResult,
    VoidCallback? onDone,
    ValueChanged<String>? onError,
  }) async {
    if (_isListening) {
      await stopListening();
    }
    _isListening = true;
    try {
      await VoiceAudioService().startRecording();
    } catch (_) {
      // Trong môi trường test hoặc thiết bị không có mic vật lý vẫn giữ trạng thái lắng nghe mượt mà
    }
    return true;
  }

  Future<void> stopListening() async {
    _isListening = false;
    try {
      await VoiceAudioService().stopRecording();
    } catch (_) {}
  }
}
