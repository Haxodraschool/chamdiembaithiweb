import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'dashboard_screen.dart';
import 'exams_screen.dart';
import 'scan_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthService>().refreshMe();
    });
  }

  final List<Widget> _screens = const [
    DashboardScreen(),
    ExamsScreen(),
    ScanScreen(),
    HistoryScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.layoutDashboard),
              activeIcon: Icon(LucideIcons.layoutDashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.fileText),
              activeIcon: Icon(LucideIcons.fileText),
              label: 'Bài thi',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.scan),
              activeIcon: Icon(LucideIcons.scan),
              label: 'Chấm điểm',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.clock),
              activeIcon: Icon(LucideIcons.clock),
              label: 'Lịch sử',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.user),
              activeIcon: Icon(LucideIcons.user),
              label: 'Tài khoản',
            ),
          ],
        ),
      ),
    );
  }
}
