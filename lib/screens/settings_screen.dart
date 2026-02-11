import 'package:flutter/material.dart';
import '../api.dart';
import '../routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  Future<void> _logout() async {
    await Api.clearToken();
    await Api.clearUser();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      AppRoutes.onGenerateRoute(
        const RouteSettings(name: AppRoutes.login),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  title: const Text('User'),
                  subtitle: Text(
                    (_user?['username'] ?? 'Unknown').toString(),
                  ),
                ),
                const Divider(),
                const ListTile(
                  title: Text('Backup'),
                  subtitle: Text('Manual backup and sync coming soon'),
                ),
                const ListTile(
                  title: Text('Language'),
                  subtitle: Text('English'),
                ),
                const ListTile(
                  title: Text('Currency'),
                  subtitle: Text('AED'),
                ),
                const ListTile(
                  title: Text('App Lock'),
                  subtitle: Text('Disabled'),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Logout'),
                  onTap: _logout,
                ),
              ],
            ),
    );
  }
}
