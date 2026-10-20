import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase Options for project `fhub-1c45b`
class DefaultFirebaseOptions {
  static const String defaultProjectId = 'fhub-1c45b';
  static const String defaultAuthDomain = 'fhub-1c45b.firebaseapp.com';
  static const String defaultStorageBucket = 'fhub-1c45b.firebasestorage.app';

  /// SePay Sandbox API Key for QR payment gateway
  static const String sepayApiKey =
      'ZMSQWHDK3RPRBDC08DX9FVJ8TG9UEJYYS2M5A4VGWH7EOLOE6BXPXL1QNWTVMNOK';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAvbv3nd6uMVxjgbGKj8fEDX6koS2GY7A8',
    appId: '1:698012966949:web:6dc9335202a239fae85fcc',
    messagingSenderId: '698012966949',
    projectId: defaultProjectId,
    authDomain: defaultAuthDomain,
    storageBucket: defaultStorageBucket,
    measurementId: 'G-0VSSJ5E3ZE',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAvbv3nd6uMVxjgbGKj8fEDX6koS2GY7A8',
    appId: '1:698012966949:web:6dc9335202a239fae85fcc',
    messagingSenderId: '698012966949',
    projectId: defaultProjectId,
    storageBucket: defaultStorageBucket,
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAvbv3nd6uMVxjgbGKj8fEDX6koS2GY7A8',
    appId: '1:698012966949:web:6dc9335202a239fae85fcc',
    messagingSenderId: '698012966949',
    projectId: defaultProjectId,
    storageBucket: defaultStorageBucket,
    iosBundleId: 'com.example.fhub',
  );
}
