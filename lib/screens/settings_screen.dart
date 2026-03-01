import 'package:flutter/material.dart';
import '../api.dart';
import '../access_control.dart';
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
    const brandBlue = Color(0xFF1E5EFF);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0C1434),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F1)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 14,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 22,
                        backgroundColor: Color(0xFFEAF0FF),
                        child: Icon(Icons.person_outline, color: brandBlue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Signed in as',
                              style: TextStyle(color: Color(0xFF6D7486)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (_user?['username'] ?? 'Unknown').toString(),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0C1434),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F1)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 14,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _settingItem(
                        icon: Icons.backup_outlined,
                        title: 'Backup',
                        subtitle: 'Manual backup and sync coming soon',
                      ),
                      _divider(),
                      _settingItem(
                        icon: Icons.language_outlined,
                        title: 'Language',
                        subtitle: 'English',
                      ),
                      _divider(),
                      _settingItem(
                        icon: Icons.currency_exchange,
                        title: 'Currency',
                        subtitle: 'AED',
                      ),
                      _divider(),
                      _settingItem(
                        icon: Icons.lock_outline,
                        title: 'App Lock',
                        subtitle: 'Disabled',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (AccessControl.isSuperUser(_user))
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F1)),
                    ),
                    child: _settingItem(
                      icon: Icons.group_add_outlined,
                      title: 'Create User',
                      subtitle: 'Add sub users and assign access controls',
                      onTap: () {
                        Navigator.push(
                          context,
                          AppRoutes.onGenerateRoute(
                            const RouteSettings(name: AppRoutes.createUser),
                          ),
                        );
                      },
                    ),
                  ),
                if (AccessControl.isSuperUser(_user)) const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F1)),
                  ),
                  child: _settingItem(
                    icon: Icons.logout,
                    title: 'Logout',
                    subtitle: 'Sign out from this device',
                    iconColor: const Color(0xFFC6284D),
                    onTap: _logout,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 60, endIndent: 16);

  Widget _settingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    Color iconColor = const Color(0xFF1E5EFF),
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xFFEAF0FF),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF0C1434),
        ),
      ),
      subtitle: Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
