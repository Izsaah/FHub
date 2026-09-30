import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../../Long/screens/main_navigation.dart';
import 'auth_screen.dart';
import 'register_view.dart';
import 'update_password_view.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _resolveSession();
  }

  Future<void> _resolveSession() async {
    if (!AuthService.passwordRecoveryNavigationHandled &&
        (AuthService.passwordRecoveryInProgress ||
            AuthService.isPasswordRecoveryRedirect)) {
      if (!mounted) return;
      AuthService.passwordRecoveryNavigationHandled = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const UpdatePasswordView()),
      );
      return;
    }

    final hasSession = await _authService.hasValidSession();
    if (!mounted) return;

    // The recovery event can arrive while session validation is running.
    // Re-check it here so Splash cannot overwrite UpdatePasswordView with Home.
    if (!AuthService.passwordRecoveryNavigationHandled &&
        (AuthService.passwordRecoveryInProgress ||
            AuthService.isPasswordRecoveryRedirect)) {
      AuthService.passwordRecoveryNavigationHandled = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const UpdatePasswordView()),
      );
      return;
    }

    final user = _authService.getCurrentUser();
    final providers = user?.appMetadata['providers'];
    final isGoogleUser =
        user != null &&
        (user.appMetadata['provider'] == 'google' ||
            (providers is List && providers.contains('google')));
    final needsGoogleRegistration =
        hasSession &&
        isGoogleUser &&
        !(await _authService.hasUserProfile(user));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => !hasSession
            ? const AuthScreen()
            : needsGoogleRegistration
            ? RegisterView(
                initialEmail: user.email ?? '',
                isGoogleRegistration: true,
              )
            : const MainNavigation(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
