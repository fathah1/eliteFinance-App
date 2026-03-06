import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../routes.dart';
import '../widgets/app_brand_logo.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _businessController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _register() async {
    if (_usernameController.text.isEmpty ||
        _nameController.text.isEmpty ||
        _businessController.text.isEmpty) {
      setState(() {
        _error = 'Username, name, and business are required.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await Api.register(
        username: _usernameController.text.trim(),
        name: _nameController.text.trim(),
        password: _passwordController.text,
        businessName: _businessController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
      );

      if (data['user'] is Map<String, dynamic>) {
        final user =
            Map<String, dynamic>.from(data['user'] as Map<String, dynamic>);
        if (data['permissions'] is Map<String, dynamic>) {
          user['permissions'] = data['permissions'];
        }
        if (data['business_ids'] is List) {
          user['business_ids'] = data['business_ids'];
        }
        await Api.saveUser(user);
        await Api.saveOfflineLoginCredential(
          username: _usernameController.text.trim(),
          user: user,
          password: _passwordController.text,
          salt: (((data['offline_auth'] as Map?)?['salt']) ??
                  user['offline_auth_salt'])
              ?.toString(),
          version: int.tryParse((((data['offline_auth'] as Map?)?['version']) ??
                      user['offline_auth_version'] ??
                      1)
                  .toString()) ??
              1,
        );
      }

      if (data['business'] is Map<String, dynamic>) {
        final b = data['business'] as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('active_business_server_id', b['id'] as int);
        await prefs.setString('active_business_name', b['name'] as String);
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
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _businessController.dispose();
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
                  'Create Account',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: Color(0xFF0C1434),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Set up your business profile',
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
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: 'Full name',
                          filled: true,
                          fillColor: const Color(0xFFF7F9FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _phoneController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: 'Phone (optional)',
                          filled: true,
                          fillColor: const Color(0xFFF7F9FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.phone_outlined),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _businessController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: 'Business name',
                          filled: true,
                          fillColor: const Color(0xFFF7F9FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.storefront_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        onSubmitted: (_) => _loading ? null : _register(),
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
                          onPressed: _loading ? null : _register,
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
                                  'Create Account',
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
                  onPressed: _loading ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Already have an account? Sign in',
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
