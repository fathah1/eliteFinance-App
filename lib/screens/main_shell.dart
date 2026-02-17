import 'package:flutter/material.dart';
import '../api.dart';
import '../access_control.dart';
import 'bills_screen.dart';
import 'home_screen.dart';
import 'items_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await Api.getUser();
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final showParties = AccessControl.canView(_user, 'parties');
    final showBills = AccessControl.canView(_user, 'bills');
    final showItems = AccessControl.canView(_user, 'items');

    final pages = <Widget>[];
    final navItems = <BottomNavigationBarItem>[];

    if (showParties) {
      pages.add(const HomeScreen());
      navItems.add(const BottomNavigationBarItem(
        icon: Icon(Icons.group),
        label: 'Parties',
      ));
    }
    if (showBills) {
      pages.add(const BillsScreen());
      navItems.add(const BottomNavigationBarItem(
        icon: Icon(Icons.receipt_long),
        label: 'Bills',
      ));
    }
    if (showItems) {
      pages.add(const ItemsScreen());
      navItems.add(const BottomNavigationBarItem(
        icon: Icon(Icons.inventory_2),
        label: 'Items',
      ));
    }

    if (pages.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No module access assigned for this user.')),
      );
    }

    if (_index >= pages.length) {
      _index = 0;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF0B4F9E),
          unselectedItemColor: const Color(0xFF6C7A96),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          backgroundColor: Colors.white,
          items: navItems,
        ),
      ),
    );
  }
}
