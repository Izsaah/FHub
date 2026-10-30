import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';

/// Triển khai Web Speech API chính chủ cho trình duyệt (Chrome / Edge / Safari)
/// - Text-to-Speech (TTS): window.speechSynthesis đọc phản hồi tiếng Việt / tiếng Anh tự nhiên.
/// - Speech-to-Text (STT): webkitSpeechRecognition / SpeechRecognition nhận diện giọng nói trực tiếp.
class AiSpeechPlatform {
  AiSpeechPlatform._();
  static final AiSpeechPlatform instance = AiSpeechPlatform._();

  bool _isSpeaking = false;
  bool _isListening = false;
  JSObject? _activeRecognition;

  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;

  bool get isSttSupported {
    return globalContext.has('webkitSpeechRecognition') ||
        globalContext.has('SpeechRecognition');
  }

  bool get isTtsSupported {
    return globalContext.has('speechSynthesis') &&
        globalContext.has('SpeechSynthesisUtterance');
  }

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

    if (!isTtsSupported) {
      onDone?.call();
      return;
    }

    try {
      final synth = globalContext['speechSynthesis'] as JSObject?;
      final utteranceCtor =
          globalContext['SpeechSynthesisUtterance'] as JSFunction?;
      if (synth == null || utteranceCtor == null) {
        onDone?.call();
        return;
      }

      synth.callMethod('cancel'.toJS);
      final utterance = utteranceCtor.callAsConstructor<JSObject>(cleaned.toJS);
      final targetLang = isEnglish ? 'en-US' : 'vi-VN';
      utterance['lang'] = targetLang.toJS;
      utterance['rate'] = 1.02.toJS;
      utterance['pitch'] = 1.0.toJS;

      // Chọn giọng đọc phù hợp nhất nếu trình duyệt đã tải danh sách voices
      try {
        final voices = synth.callMethod<JSArray>('getVoices'.toJS);
        final len = voices.length;
        final langPrefix = isEnglish ? 'en' : 'vi';
        for (int i = 0; i < len; i++) {
          final v = voices[i] as JSObject?;
          if (v != null) {
            final vLang = (v['lang'] as JSString?)?.toDart.toLowerCase() ?? '';
            if (vLang.startsWith(langPrefix)) {
              utterance['voice'] = v;
              break;
            }
          }
        }
      } catch (_) {}

      _isSpeaking = true;

      utterance['onend'] = ((JSAny? _) {
        _isSpeaking = false;
        onDone?.call();
      }).toJS;

      utterance['onerror'] = ((JSAny? _) {
        _isSpeaking = false;
        onDone?.call();
      }).toJS;

      synth.callMethod('speak'.toJS, utterance);
    } catch (e) {
      debugPrint('AiSpeechPlatform.speak error: $e');
      _isSpeaking = false;
      onDone?.call();
    }
  }

  Future<void> stopSpeaking() async {
    _isSpeaking = false;
    try {
      if (globalContext.has('speechSynthesis')) {
        final synth = globalContext['speechSynthesis'] as JSObject?;
        synth?.callMethod('cancel'.toJS);
      }
    } catch (_) {}
  }

  Future<bool> startListening({
    required bool isEnglish,
    required ValueChanged<String> onResult,
    VoidCallback? onDone,
    ValueChanged<String>? onError,
  }) async {
    await stopSpeaking();
    if (_isListening) {
      await stopListening();
    }

    if (!isSttSupported) {
      onError?.call(
        isEnglish
            ? 'Speech recognition is not supported in this browser. Please use Chrome or Edge.'
            : 'Trình duyệt hiện tại chưa hỗ trợ nhận diện giọng nói. Vui lòng dùng Chrome hoặc Edge.',
      );
      return false;
    }

    try {
      final ctor = (globalContext['SpeechRecognition'] ??
          globalContext['webkitSpeechRecognition']) as JSFunction?;
      if (ctor == null) return false;

      final recognition = ctor.callAsConstructor<JSObject>();
      _activeRecognition = recognition;
      _isListening = true;

      recognition['lang'] = (isEnglish ? 'en-US' : 'vi-VN').toJS;
      recognition['continuous'] = false.toJS;
      recognition['interimResults'] = true.toJS;
      recognition['maxAlternatives'] = 1.toJS;

      recognition['onresult'] = ((JSObject event) {
        try {
          final results = event['results'] as JSObject?;
          if (results == null) return;
          final length = (results['length'] as JSNumber?)?.toDartInt ?? 0;
          final buffer = StringBuffer();
          for (int i = 0; i < length; i++) {
            final resultItem = results[i.toString()] as JSObject?;
            if (resultItem != null) {
              final alt = resultItem['0'] as JSObject?;
              final transcript =
                  (alt?['transcript'] as JSString?)?.toDart ?? '';
              buffer.write(transcript);
            }
          }
          final text = buffer.toString().trim();
          if (text.isNotEmpty) {
            onResult(text);
          }
        } catch (e) {
          debugPrint('STT onresult parse error: $e');
        }
      }).toJS;

      recognition['onerror'] = ((JSObject event) {
        final errCode = (event['error'] as JSString?)?.toDart ?? 'unknown';
        debugPrint('STT error: $errCode');
        _isListening = false;
        if (errCode == 'not-allowed' || errCode == 'service-not-allowed') {
          onError?.call(
            isEnglish
                ? 'Microphone access denied. Please allow microphone permission in your browser.'
                : 'Chưa cấp quyền Micro. Vui lòng cho phép quyền Micro trên thanh địa chỉ trình duyệt.',
          );
        } else if (errCode != 'aborted' && errCode != 'no-speech') {
          onError?.call(
            isEnglish
                ? 'Could not recognize speech ($errCode). Please try again.'
                : 'Không nhận diện được giọng nói ($errCode). Bạn hãy thử nói lại nhé.',
          );
        }
        onDone?.call();
      }).toJS;

      recognition['onend'] = ((JSAny? _) {
        _isListening = false;
        onDone?.call();
      }).toJS;

      recognition.callMethod('start'.toJS);
      return true;
    } catch (e) {
      debugPrint('AiSpeechPlatform.startListening error: $e');
      _isListening = false;
      onError?.call(
        isEnglish
            ? 'Failed to start microphone: $e'
            : 'Không thể khởi động Micro: $e',
      );
      return false;
    }
  }

  Future<void> stopListening() async {
    _isListening = false;
    final rec = _activeRecognition;
    _activeRecognition = null;
    if (rec != null) {
      try {
        rec.callMethod('stop'.toJS);
      } catch (_) {}
    }
  }
}
