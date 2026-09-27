import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'Long/screens/main_navigation.dart';
import 'Thinh/screens/auth_screen.dart';
import 'Thinh/services/auth_service.dart';
import 'Thinh/screens/register_view.dart';
import 'Thinh/screens/splash_screen.dart';
import 'Thinh/screens/update_password_view.dart';
import 'Thinh/services/web_session_sync_stub.dart'
    if (dart.library.html) 'Thinh/services/web_session_sync_web.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
  );
  runApp(const FamilyHubApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

class FamilyHubApp extends StatefulWidget {
  const FamilyHubApp({super.key});

  @override
  State<FamilyHubApp> createState() => _FamilyHubAppState();
}

class _FamilyHubAppState extends State<FamilyHubApp> {
  late final StreamSubscription<AuthState> _authSub;
  final WebSessionSync _webSessionSync = WebSessionSync();
  bool _recoveryBroadcasted = false;

  @override
  void initState() {
    super.initState();
    // Lắng nghe sự kiện click link Reset Password (Magic Link)
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        AuthService.passwordRecoveryInProgress = true;
        if (AuthService.passwordRecoveryNavigationHandled) return;
        AuthService.passwordRecoveryNavigationHandled = true;
        // Dùng navigatorKey để ép chuyển trang, đảm bảo hoạt động 100%
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (context) => const UpdatePasswordView()),
        );
      } else if (data.event == AuthChangeEvent.signedIn &&
          AuthService.googleSignInInProgress &&
          navigatorKey.currentState != null) {
        AuthService.googleSignInInProgress = false;
        _routeAfterGoogleSignIn(data.session?.user);
      }
    });
    _webSessionSync.start(_routeExistingTabToLogin);
  }

  void _routeExistingTabToLogin() {
    if (!mounted || navigatorKey.currentState == null) return;
    navigatorKey.currentState!.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  Future<void> _routeAfterGoogleSignIn(User? user) async {
    final googleUser = user ?? Supabase.instance.client.auth.currentUser;
    if (googleUser == null) return;

    final hasProfile = await AuthService().hasUserProfile(googleUser);
    if (!mounted || navigatorKey.currentState == null) return;

    navigatorKey.currentState!.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => hasProfile
            ? const MainNavigation()
            : RegisterView(
                initialEmail: googleUser.email ?? '',
                isGoogleRegistration: true,
              ),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _authSub.cancel();
    _webSessionSync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRecoveryRedirect = AuthService.isPasswordRecoveryRedirect;
    if (isRecoveryRedirect) {
      AuthService.passwordRecoveryNavigationHandled = true;
      if (!_recoveryBroadcasted) {
        _recoveryBroadcasted = true;
        _webSessionSync.markRecovery();
      }
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Family Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3FBF8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005F50),
          primary: const Color(0xFF005F50),
          surface: const Color(0xFFF3FBF8),
          error: const Color(0xFFBA1A1A),
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF151D1B),
          ),
          bodyMedium: TextStyle(fontSize: 16, color: Color(0xFF151D1B)),
          bodySmall: TextStyle(fontSize: 14, color: Color(0xFF3E4946)),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 1,
          shadowColor: Colors.black12,
          backgroundColor: Color(0xFFEDF5F2),
          foregroundColor: Color(0xFF005F50),
        ),
      ),
      home: isRecoveryRedirect
          ? const UpdatePasswordView()
          : const SplashScreen(),
    );
  }
}
