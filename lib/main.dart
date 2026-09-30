import 'package:flutter/material.dart';
import 'Vinh/reminder/reminder.dart';

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
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: .center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D7A68),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.notifications_active),
              label: const Text(
                'Mở Reminder Management (Vinh)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ReminderListScreen(
                      familyId: 'family_1',
                      currentUserId: 'user_minh',
                      currentUserName: 'Minh',
                      familyMembers: const [
                        FamilyMember(
                          id: 'user_minh',
                          name: 'Minh',
                          role: 'Owner',
                          familyId: 'family_1',
                        ),
                        FamilyMember(
                          id: 'user_mom',
                          name: 'Mom',
                          role: 'Member',
                          familyId: 'family_1',
                        ),
                        FamilyMember(
                          id: 'user_dad',
                          name: 'Dad',
                          role: 'Member',
                          familyId: 'family_1',
                        ),
                      ],
                      repository: InMemoryReminderRepository(),
                    ),
                  ),
                );
              },
            ),
          ],
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
