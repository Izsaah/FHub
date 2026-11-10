import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../Ai/services/gemini_chat_service.dart';
import 'voice_audio_service.dart';

/// Triển khai nhận diện giọng nói (STT) và phát âm phản hồi (TTS) cho nền tảng Native (Android/iOS/Desktop).
class AiSpeechPlatform {
  AiSpeechPlatform._();
  static final AiSpeechPlatform instance = AiSpeechPlatform._();

  bool _isSpeaking = false;
  bool _isListening = false;
  Timer? _speakTimer;
  StreamSubscription<Map<String, dynamic>>? _playbackSub;

  ValueChanged<String>? _onResult;
  VoidCallback? _onDone;
  ValueChanged<String>? _onError;
  bool _isEnglish = false;

  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;
  bool get isSttSupported => true;
  bool get isTtsSupported => true;

  /// Làm sạch văn bản trước khi đọc (bỏ ký tự markdown và emoji để giọng đọc tự nhiên)
  String _cleanTextForSpeech(String raw) {
    return raw
        .replaceAll(RegExp(r'[*_`#~>]'), '')
        .replaceAll(RegExp(r'•|- '), ', ')
        .replaceAll(
          RegExp(
            r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]',
            unicode: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> speak(
    String text, {
    required bool isEnglish,
    VoidCallback? onDone,
  }) async {
    await stopSpeaking();

    final cleaned = _cleanTextForSpeech(text);
    if (cleaned.isEmpty) {
      onDone?.call();
      return;
    }

    _isSpeaking = true;

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        // Giới hạn câu đọc súc tích tự nhiên (tối đa ~180 ký tự đầu tiên để phản hồi tức thì)
        String speakChunk = cleaned;
        if (speakChunk.length > 180) {
          final periodIdx = speakChunk.indexOf('.', 80);
          if (periodIdx != -1 && periodIdx < 200) {
            speakChunk = speakChunk.substring(0, periodIdx + 1);
          } else {
            final spaceIdx = speakChunk.lastIndexOf(' ', 180);
            if (spaceIdx > 50) {
              speakChunk = speakChunk.substring(0, spaceIdx);
            } else {
              speakChunk = speakChunk.substring(0, 180);
            }
          }
        }

        final lang = isEnglish ? 'en' : 'vi';
        final url =
            'https://translate.google.com/translate_tts?ie=UTF-8&tl=$lang&client=tw-ob&q=${Uri.encodeComponent(speakChunk)}';

        final res = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          final dir = await getTemporaryDirectory();
          final filePath =
              '${dir.path}/tts_response_${DateTime.now().millisecondsSinceEpoch}.mp3';
          final file = File(filePath);
          await file.writeAsBytes(res.bodyBytes);

          _playbackSub?.cancel();
          _playbackSub = VoiceAudioService().playbackStateStream.listen((event) {
            if (event['id'] == 'ai_speech' && event['isCompleted'] == true) {
              _playbackSub?.cancel();
              _isSpeaking = false;
              onDone?.call();
            }
          });

          await VoiceAudioService().playAudio(
            reminderId: 'ai_speech',
            audioPath: filePath,
          );
          return;
        }
      } catch (e) {
        debugPrint('AiSpeechPlatform TTS audio error: $e');
      }
    }

    // Dự phòng khi offline, unit test hoặc lỗi mạng: ước lượng thời lượng đọc tự nhiên
    final wordCount = cleaned.split(RegExp(r'\s+')).length;
    final seconds = (wordCount ~/ 3).clamp(2, 6);
    _speakTimer = Timer(Duration(seconds: seconds), () {
      _isSpeaking = false;
      onDone?.call();
    });
  }

  Future<void> stopSpeaking() async {
    _speakTimer?.cancel();
    _speakTimer = null;
    _playbackSub?.cancel();
    _playbackSub = null;
    _isSpeaking = false;
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        await VoiceAudioService().stopAudio();
      } catch (_) {}
    }
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
    _onResult = onResult;
    _onDone = onDone;
    _onError = onError;
    _isEnglish = isEnglish;

    try {
      await VoiceAudioService().startRecording();
      return true;
    } catch (e) {
      _isListening = false;
      _onError?.call(e.toString());
      return false;
    }
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    _isListening = false;
    try {
      final recordedPath = await VoiceAudioService().stopRecording();
      if (recordedPath != null && recordedPath.isNotEmpty) {
        final text = await _transcribeAudio(recordedPath, _isEnglish);
        if (text != null && text.trim().isNotEmpty) {
          _onResult?.call(text.trim());
        }
      }
      _onDone?.call();
    } catch (e) {
      debugPrint('AiSpeechPlatform stopListening error: $e');
      _onError?.call(e.toString());
    }
  }

  Future<String?> _transcribeAudio(String path, bool isEnglish) async {
    try {
      final apiKey = GeminiChatService.instance.effectiveApiKey;
      if (apiKey.isEmpty) return null;

      final file = File(path);
      if (!await file.exists() || await file.length() == 0) return null;
      final bytes = await file.readAsBytes();
      final ext = path.toLowerCase();
      final mimeType = ext.endsWith('.wav') ? 'audio/wav' : 'audio/m4a';
      final lang = isEnglish ? 'tiếng Anh' : 'tiếng Việt';

      final prompt = 'Chuyển file âm thanh này thành văn bản $lang chính xác. '
          'Chỉ trả về đúng nội dung câu nói của người dùng, không thêm định dạng, markdown, lời dẫn hay giải thích nào.';

      final modelsToTry = [
        'gemini-2.5-flash',
        'gemini-2.0-flash',
        'gemini-1.5-flash',
      ];

      for (final candidate in modelsToTry) {
        try {
          final model = GenerativeModel(
            model: candidate,
            apiKey: apiKey,
          );
          final response = await model.generateContent([
            Content.multi([
              DataPart(mimeType, bytes),
              TextPart(prompt),
            ]),
          ]).timeout(const Duration(seconds: 8));

          final text = response.text?.trim();
          if (text != null &&
              text.isNotEmpty &&
              !text.toLowerCase().contains('không có lời nói') &&
              !text.toLowerCase().contains('chỉ có tiếng bíp')) {
            return text;
          }
        } catch (e) {
          debugPrint('AiSpeechPlatform transcribe audio with $candidate error: $e');
        }
      }
    } catch (e) {
      debugPrint('AiSpeechPlatform transcribe audio error: $e');
    }
    return null;
  }
}
