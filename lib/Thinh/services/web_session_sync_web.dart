// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;

import 'web_session_sync_stub.dart';

class WebSessionSync {
  static const _recoveryKey = 'fhub_password_recovery';
  StreamSubscription<html.StorageEvent>? _subscription;

  void start(RecoveryCallback onRecovery) {
    _subscription = html.window.onStorage.listen((event) {
      if (event.key == _recoveryKey && event.newValue != null) {
        onRecovery();
      }
    });
  }

  void markRecovery() {
    html.window.localStorage[_recoveryKey] = DateTime.now()
        .millisecondsSinceEpoch
        .toString();
  }

  void dispose() {
    _subscription?.cancel();
  }
}
