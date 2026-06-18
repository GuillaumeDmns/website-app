import 'package:flutter/material.dart';
import 'package:website_app/screens/lines.dart';

import '../utils/constants.dart' as constants;
import 'map.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _currentPageIndex = 0;
  final List<Widget> _screens = [MapScreen(), LinesScreen()];
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        height: constants.navigationBarHeight,
        onDestinationSelected: _onDestinationTap,
        selectedIndex: _currentPageIndex,
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.map_rounded),
            icon: Icon(Icons.map_outlined),
            label: 'Carte',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.train_rounded),
            icon: Icon(Icons.train_outlined),
            label: 'Lignes',
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: _screens[_currentPageIndex],
      ),
    );
  }

  void _onDestinationTap(int index) {
    if (index == _currentPageIndex) return;
    _fadeController.reset();
    setState(() {
      _currentPageIndex = index;
    });
    _fadeController.forward();
  }
}
