typedef RecoveryCallback = void Function();

class WebSessionSync {
  void start(RecoveryCallback onRecovery) {}

  void markRecovery() {}

  void dispose() {}
}
