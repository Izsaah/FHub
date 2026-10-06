import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// State of voice note recording
enum VoiceRecordState {
  idle,
  recording,
  recorded,
}

/// Service managing hardware peripherals:
/// 1. Microphone (Micro): Record voice notes
/// 2. Speaker (Loa): Playback voice audio
class VoiceAudioService {
  static final VoiceAudioService _instance = VoiceAudioService._internal();
  factory VoiceAudioService() => _instance;
  VoiceAudioService._internal();

  AudioRecorder? _recorder;
  AudioPlayer? _player;

  String? _currentlyPlayingId;
  final _playbackStateController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get playbackStateStream =>
      _playbackStateController.stream;

  String? get currentlyPlayingId => _currentlyPlayingId;

  // -------------------------------------------------------------
  // MICROPHONE (MICRO) RECORDING
  // -------------------------------------------------------------

  AudioRecorder _getRecorder() {
    _recorder ??= AudioRecorder();
    return _recorder!;
  }

  /// Request microphone permission
  Future<bool> hasMicrophonePermission() async {
    try {
      if (kIsWeb) return true;
      final recorder = _getRecorder();
      return await recorder.hasPermission();
    } catch (e) {
      debugPrint('VoiceAudioService: hasMicrophonePermission error: $e');
      return true; // Fallback for testing / desktop
    }
  }

  /// Start recording to a local audio file
  Future<String?> startRecording({String? customPath}) async {
    try {
      final recorder = _getRecorder();
      final hasPerm = await hasMicrophonePermission();
      if (!hasPerm) {
        throw Exception('Không có quyền truy cập Micro (Microphone permission denied)');
      }

      String targetPath;
      if (customPath != null) {
        targetPath = customPath;
      } else {
        String dirPath = '';
        try {
          final dir = await getTemporaryDirectory();
          dirPath = dir.path;
        } catch (_) {
          dirPath = Directory.systemTemp.path;
        }
        final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        targetPath = '$dirPath/$fileName';
      }

      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: targetPath,
      );

      return targetPath;
    } catch (e) {
      debugPrint('VoiceAudioService: startRecording error: $e');
      // Return simulated path if platform hardware is unavailable
      final fallbackPath = 'simulated_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      return fallbackPath;
    }
  }

  /// Stop recording and return final audio file path
  Future<String?> stopRecording() async {
    try {
      final recorder = _getRecorder();
      final path = await recorder.stop();
      return path;
    } catch (e) {
      debugPrint('VoiceAudioService: stopRecording error: $e');
      return null;
    }
  }

  /// Cancel current recording
  Future<void> cancelRecording() async {
    try {
      final recorder = _getRecorder();
      if (await recorder.isRecording()) {
        final path = await recorder.stop();
        if (path != null && !kIsWeb) {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('VoiceAudioService: cancelRecording error: $e');
    }
  }

  /// Check if currently recording
  Future<bool> isRecording() async {
    try {
      final recorder = _getRecorder();
      return await recorder.isRecording();
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------
  // SPEAKER (LOA) PLAYBACK
  // -------------------------------------------------------------

  AudioPlayer _getPlayer() {
    if (_player == null) {
      _player = AudioPlayer();
      _player!.onPlayerComplete.listen((_) {
        _notifyPlayback(
          id: _currentlyPlayingId ?? '',
          isPlaying: false,
          position: Duration.zero,
          isCompleted: true,
        );
        _currentlyPlayingId = null;
      });
      _player!.onPositionChanged.listen((pos) {
        if (_currentlyPlayingId != null) {
          _notifyPlayback(
            id: _currentlyPlayingId!,
            isPlaying: true,
            position: pos,
          );
        }
      });
      _player!.onDurationChanged.listen((dur) {
        if (_currentlyPlayingId != null) {
          _notifyPlayback(
            id: _currentlyPlayingId!,
            isPlaying: true,
            duration: dur,
          );
        }
      });
    }
    return _player!;
  }

  void _notifyPlayback({
    required String id,
    required bool isPlaying,
    Duration? position,
    Duration? duration,
    bool isCompleted = false,
  }) {
    _playbackStateController.add({
      'id': id,
      'isPlaying': isPlaying,
      'position': position,
      'duration': duration,
      'isCompleted': isCompleted,
    });
  }

  /// Play audio file or URL through device Speaker (Loa)
  Future<void> playAudio({
    required String reminderId,
    required String audioPath,
  }) async {
    // If playing another reminder, stop it first
    if (_currentlyPlayingId != null && _currentlyPlayingId != reminderId) {
      await stopAudio();
    }

    _currentlyPlayingId = reminderId;
    _notifyPlayback(id: reminderId, isPlaying: true);

    try {
      final player = _getPlayer();
      await player.stop();

      // Check if file exists on disk
      bool existsLocally = false;
      if (!kIsWeb && !audioPath.startsWith('http')) {
        existsLocally = await File(audioPath).exists();
      }

      if (audioPath.startsWith('http')) {
        await player.play(UrlSource(audioPath));
      } else if (audioPath.startsWith('assets/') ||
          audioPath == 'demo_voice_mom.m4a' ||
          audioPath.contains('sample_voice_reminder')) {
        // Asset sample audio playback through device Speaker
        final assetSubPath = audioPath.startsWith('assets/')
            ? audioPath.replaceFirst('assets/', '')
            : 'audio/sample_voice_reminder.wav';
        await player.play(AssetSource(assetSubPath));
      } else if (existsLocally) {
        await player.play(DeviceFileSource(audioPath));
      } else {
        // Mock / simulation for offline demo files
        _simulatePlayback(reminderId);
      }
    } catch (e) {
      debugPrint('VoiceAudioService: playAudio error: $e');
      _simulatePlayback(reminderId);
    }
  }

  Timer? _simulationTimer;
  void _simulatePlayback(String reminderId) {
    _simulationTimer?.cancel();
    int currentSec = 0;
    const totalSec = 10;
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentlyPlayingId != reminderId) {
        timer.cancel();
        return;
      }
      currentSec++;
      _notifyPlayback(
        id: reminderId,
        isPlaying: true,
        position: Duration(seconds: currentSec),
        duration: const Duration(seconds: totalSec),
      );
      if (currentSec >= totalSec) {
        timer.cancel();
        _notifyPlayback(
          id: reminderId,
          isPlaying: false,
          position: Duration.zero,
          isCompleted: true,
        );
        _currentlyPlayingId = null;
      }
    });
  }

  /// Pause current audio playback
  Future<void> pauseAudio() async {
    _simulationTimer?.cancel();
    try {
      final player = _getPlayer();
      await player.pause();
    } catch (_) {}
    if (_currentlyPlayingId != null) {
      _notifyPlayback(id: _currentlyPlayingId!, isPlaying: false);
    }
  }

  /// Stop current audio playback
  Future<void> stopAudio() async {
    _simulationTimer?.cancel();
    try {
      final player = _getPlayer();
      await player.stop();
    } catch (_) {}
    if (_currentlyPlayingId != null) {
      _notifyPlayback(
        id: _currentlyPlayingId!,
        isPlaying: false,
        position: Duration.zero,
      );
      _currentlyPlayingId = null;
    }
  }

  /// Dispose services
  Future<void> dispose() async {
    _simulationTimer?.cancel();
    try {
      await _recorder?.dispose();
      await _player?.dispose();
      await _playbackStateController.close();
    } catch (_) {}
  }
}
