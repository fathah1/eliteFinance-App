import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../db.dart';
import '../routes.dart';

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
      if (data['business_ids'] is List &&
          (data['business_ids'] as List).isNotEmpty) {
        final ids = (data['business_ids'] as List)
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toList();
        if (ids.isNotEmpty) {
          final businesses = await Api.getBusinesses();
          if (businesses.isNotEmpty) {
            final first = businesses.cast<Map<String, dynamic>>().firstWhere(
                  (b) => ids.contains((b['id'] as num).toInt()),
                  orElse: () => businesses.cast<Map<String, dynamic>>().first,
                );
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt(
                'active_business_server_id', (first['id'] as num).toInt());
            await prefs.setString(
              'active_business_name',
              (first['name'] ?? 'Business').toString(),
            );
          }
        }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Login'),
            ),
            const SizedBox(height: 12),
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
              child: const Text('Create an account'),
            ),
          ],
        ),
      ),
    );
  }
}
