import 'package:flutter/material.dart';
import 'package:loading/core/app_colors.dart';
import 'package:loading/core/responsive.dart';
import 'package:loading/features/browser/ui/browser_screen.dart';
import 'package:loading/features/media/ui/home_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final tablet = Responsive.isTablet(context);
    final page = _index == 0 ? const HomeScreen() : const BrowserScreen();
    return Scaffold(
      body: tablet
          ? SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    backgroundColor: AppColors.surface,
                    indicatorColor: AppColors.accent,
                    labelType: NavigationRailLabelType.all,
                    selectedIconTheme: const IconThemeData(color: AppColors.ink),
                    unselectedIconTheme: const IconThemeData(color: AppColors.muted),
                    onDestinationSelected: (index) => setState(() => _index = index),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.link),
                        label: Text('ลิงก์'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.public),
                        label: Text('หน้าเว็บ'),
                      ),
                    ],
                  ),
                  Expanded(child: page),
                ],
              ),
            )
          : page,
      bottomNavigationBar: tablet
          ? null
          : NavigationBar(
              selectedIndex: _index,
              backgroundColor: AppColors.surface,
              indicatorColor: AppColors.accent,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.link), label: 'ลิงก์'),
                NavigationDestination(icon: Icon(Icons.public), label: 'หน้าเว็บ'),
              ],
            ),
    );
  }
}
