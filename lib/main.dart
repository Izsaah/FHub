import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Long/screens/main_navigation.dart';
import 'Thinh/screens/auth_screen.dart';
import 'Thinh/screens/update_password_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
  );
  runApp(const FamilyHubApp());
}

class FamilyHubApp extends StatefulWidget {
  const FamilyHubApp({super.key});

  @override
  State<FamilyHubApp> createState() => _FamilyHubAppState();
}

class _FamilyHubAppState extends State<FamilyHubApp> {
  late final StreamSubscription<AuthState> _authSub;
  bool _isRecovery = false;

  @override
  void initState() {
    super.initState();
    // Lắng nghe LIÊN TỤC — khi PKCE code exchange xong (có thể 1-3 giây sau),
    // event passwordRecovery sẽ fire và app tự chuyển sang UpdatePasswordView
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        if (mounted) {
          setState(() => _isRecovery = true);
        }
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine the home screen
    Widget homeScreen;
    if (_isRecovery) {
      homeScreen = const UpdatePasswordView();
    } else if (Supabase.instance.client.auth.currentSession != null) {
      homeScreen = const MainNavigation();
    } else {
      homeScreen = const AuthScreen();
    }

    return MaterialApp(
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
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF151D1B)),
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
      home: homeScreen,
    );
  }
}
