import 'package:flutter/material.dart';

import 'home/home_screen.dart';
import 'family/family_screen.dart';
import 'family/create_family_screen.dart';
import 'family/join_family_screen.dart';
import 'profile/profile_screen.dart';

import '../services/supabase_service.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late Future<bool> _hasFamilyFuture;

  @override
  void initState() {
    super.initState();
    _hasFamilyFuture = SupabaseService().hasFamily();
  }

  void _refreshFamilyStatus() {
    setState(() {
      _hasFamilyFuture = SupabaseService().hasFamily();
    });
  }

  final List<Widget> _screens = [
    const HomeScreen(),
    const Scaffold(
      body: Center(child: Text("Reminders Screen (Out of Scope)")),
    ),
    const FamilyScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue[800],
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: 'Reminders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.family_restroom),
            label: 'Family',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

