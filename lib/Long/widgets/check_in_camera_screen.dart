import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../Thinh/theme/app_language.dart';

class CheckInCameraScreen extends StatefulWidget {
  const CheckInCameraScreen({super.key});

  @override
  State<CheckInCameraScreen> createState() => _CheckInCameraScreenState();
}

class _CheckInCameraScreenState extends State<CheckInCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  Uint8List? _capturedPhoto;
  String? _errorMessage;
  bool _isCameraReady = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final controller = _controller;
      _controller = null;
      _initializeFuture = null;
      _isCameraReady = false;
      if (controller != null) unawaited(controller.dispose());
    } else if (state == AppLifecycleState.resumed && _capturedPhoto == null) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = AppLanguage.text(
            'Không tìm thấy máy ảnh trên thiết bị này.',
            'No camera was found on this device.',
          );
        });
        return;
      }

      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _controller = controller;
      final initializeFuture = controller.initialize();
      setState(() {
        _initializeFuture = initializeFuture;
        _errorMessage = null;
        _isCameraReady = false;
      });
      await initializeFuture;
      if (!mounted || !identical(_controller, controller)) return;
      setState(() => _isCameraReady = true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isCameraReady = false;
        _errorMessage = AppLanguage.text(
          'Không thể khởi động máy ảnh: $error',
          'Could not start the camera: $error',
        );
      });
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !_isCameraReady || _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);
    try {
      final photo = await controller.takePicture();
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() => _capturedPhoto = bytes);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLanguage.text(
          'Không thể chụp ảnh: $error',
          'Could not take the photo: $error',
        );
      });
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(AppLanguage.text('Chụp ảnh', 'Take a photo')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _capturedPhoto != null
                    ? Image.memory(
                        _capturedPhoto!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      )
                    : _errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : controller == null || _initializeFuture == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : FutureBuilder<void>(
                        future: _initializeFuture,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                AppLanguage.text(
                                  'Không thể khởi động máy ảnh: ${snapshot.error}',
                                  'Could not start the camera: ${snapshot.error}',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            );
                          }
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const CircularProgressIndicator(
                              color: Colors.white,
                            );
                          }
                          return CameraPreview(controller);
                        },
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_capturedPhoto != null)
                    OutlinedButton(
                      onPressed: () => setState(() => _capturedPhoto = null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                      child: Text(AppLanguage.text('Chụp lại', 'Retake')),
                    )
                  else
                    const SizedBox(width: 96),
                  if (_capturedPhoto == null)
                    IconButton(
                      onPressed:
                          _errorMessage != null ||
                              controller == null ||
                              !_isCameraReady ||
                              _isCapturing
                          ? null
                          : _takePhoto,
                      icon: _isCapturing
                          ? const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            )
                          : const Icon(
                              Icons.camera,
                              color: Colors.white,
                              size: 44,
                            ),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF005F50),
                        padding: const EdgeInsets.all(18),
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_capturedPhoto),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF005F50),
                        foregroundColor: Colors.white,
                      ),
                      child: Text(AppLanguage.text('Dùng ảnh', 'Use photo')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
