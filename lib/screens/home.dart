import 'package:flutter/material.dart';
import 'package:website_app/screens/lines.dart';

import 'map.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentPageIndex = 0;
  final List<Widget> _screens = [
    MapScreen(),
    LinesScreen()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: _onDestinationTap,
        selectedIndex: _currentPageIndex,
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.map),
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.calendar_month),
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Lines',
          ),
        ],
      ),
      body: _screens[_currentPageIndex]
    );
  }

  _onDestinationTap(int index) {
    setState(() {
      _currentPageIndex = index;
    });
  }
}
