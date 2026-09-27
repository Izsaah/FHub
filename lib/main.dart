import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Long/screens/main_navigation.dart';
import 'Thinh/screens/auth_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
  );
  runApp(const FamilyHubApp());
}

class FamilyHubApp extends StatelessWidget {
  const FamilyHubApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      // Route based on whether the user is already authenticated
      home: Supabase.instance.client.auth.currentSession == null
          ? const AuthScreen()
          : const MainNavigation(),
    );
  }
}
