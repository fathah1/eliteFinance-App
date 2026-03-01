import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../access_control.dart';
import '../api.dart';
import '../db.dart';
import '../routes.dart';
import '../widgets/app_brand_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  List<int> _businessIdsFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => int.tryParse(e.toString())).whereType<int>().toList();
  }

  Future<Map<String, dynamic>?> _pickBusiness(
    List<Map<String, dynamic>> businesses,
  ) async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Business',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose the business you want to open.',
                  style: TextStyle(color: Color(0xFF6D7486)),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: businesses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final b = businesses[index];
                      final name = (b['name'] ?? 'Business').toString();
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F1)),
                        ),
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFEAF0FF),
                          child: Icon(Icons.storefront_outlined,
                              color: Color(0xFF1E5EFF)),
                        ),
                        title: Text(name),
                        onTap: () => Navigator.pop(context, b),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _resolveActiveBusiness(Map<String, dynamic> loginData) async {
    final prefs = await SharedPreferences.getInstance();
    final user = await Api.getUser();
    final isSuper = AccessControl.isSuperUser(user);

    final allBusinesses =
        (await Api.getBusinesses()).cast<Map<String, dynamic>>();
    if (allBusinesses.isEmpty) {
      await prefs.remove('active_business_server_id');
      await prefs.remove('active_business_name');
      return true;
    }

    final allowedIds = _businessIdsFrom(
      loginData['business_ids'] ?? user?['business_ids'],
    );

    List<Map<String, dynamic>> available = allBusinesses;
    if (!isSuper && allowedIds.isNotEmpty) {
      available = allBusinesses.where((b) {
        final id = int.tryParse((b['id'] ?? '').toString());
        return id != null && allowedIds.contains(id);
      }).toList();
    }

    if (available.isEmpty) {
      await prefs.remove('active_business_server_id');
      await prefs.remove('active_business_name');
      return true;
    }

    Map<String, dynamic>? selected;
    if (available.length == 1) {
      selected = available.first;
    } else {
      if (!mounted) return false;
      selected = await _pickBusiness(available);
      if (selected == null) return false;
    }

    final id = int.tryParse((selected['id'] ?? '').toString());
    final name = (selected['name'] ?? 'Business').toString();
    if (id != null) {
      await prefs.setInt('active_business_server_id', id);
      await prefs.setString('active_business_name', name);
    }
    return true;
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty) {
      setState(() {
        _error = 'Please enter username.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await Api.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (data['user'] is Map<String, dynamic>) {
        await Db.instance.upsertUser(data['user'] as Map<String, dynamic>);
      }
      final businessResolved = await _resolveActiveBusiness(data);
      if (!businessResolved) {
        setState(() => _loading = false);
        return;
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        AppRoutes.onGenerateRoute(
          const RouteSettings(name: AppRoutes.home),
        ),
        (route) => false,
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Column(
              children: [
                const SizedBox(height: 12),
                const AppBrandLogo(size: 82, textSize: 28, borderRadius: 22),
                const SizedBox(height: 14),
                const Text(
                  'ECBooks',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: Color(0xFF0C1434),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sign in to continue',
                  style: TextStyle(
                    color: Color(0xFF6D7486),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 430),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F1)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: 'Username',
                          filled: true,
                          fillColor: const Color(0xFFF7F9FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        onSubmitted: (_) => _loading ? null : _login(),
                        decoration: InputDecoration(
                          hintText: 'Password',
                          filled: true,
                          fillColor: const Color(0xFFF7F9FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_error != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFFCDD2)),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFC6284D),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (_error != null) const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E5EFF),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF9CB8FF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            AppRoutes.onGenerateRoute(
                              const RouteSettings(name: AppRoutes.register),
                            ),
                          );
                        },
                  child: const Text(
                    'Create an account',
                    style: TextStyle(
                      color: Color(0xFF1E5EFF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
