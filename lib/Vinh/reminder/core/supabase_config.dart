import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://jlruiougsjjevcuiwuxd.supabase.co';
  static const String publishableKey =
      'sb_publishable_7gJDbabScyMiKqE-waWlVQ_mKICAgWA';

  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  /// Initializes Supabase with credentials from .env
  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: publishableKey,
      );
      _isInitialized = true;
    } catch (_) {
      // In tests or if already initialized / offline
    }
  }

  static SupabaseClient? get client {
    if (!_isInitialized) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
