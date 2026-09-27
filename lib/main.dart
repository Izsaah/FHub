import 'package:flutter/material.dart';
import 'Thinh/screens/auth_screen.dart';

import 'dart:async';
import 'Thinh/screens/update_password_view.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
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
    return MaterialApp(
      title: 'FHub',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      debugShowCheckedModeBanner: false,
      home: _isRecovery ? const UpdatePasswordView() : const AuthScreen(),
    );
  }
}
