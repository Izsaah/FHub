import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'Thinh/screens/splash_screen.dart';
import 'Vinh/services/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Firebase (Auth & Firestore)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully.');
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  runApp(const FamilyHubApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class FamilyHubApp extends StatelessWidget {
  const FamilyHubApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      home: const SplashScreen(),
    );
  }
}
