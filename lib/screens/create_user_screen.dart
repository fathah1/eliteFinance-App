import 'package:flutter/material.dart';

import '../api.dart';

class CreateUserScreen extends StatefulWidget {
  const CreateUserScreen({super.key});

  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  final _usernameController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _businesses = [];
  List<Map<String, dynamic>> _staff = [];
  final Set<int> _selectedBusinesses = {};

  final Map<String, Map<String, bool>> _permissions = {
    'parties': {'view': true, 'add': true, 'edit': true},
    'items': {'view': true, 'add': true, 'edit': true},
    'reports': {'view': true, 'add': false, 'edit': false},
    'sale': {'view': true, 'add': true, 'edit': true},
    'purchase': {'view': true, 'add': true, 'edit': true},
    'expense': {'view': true, 'add': true, 'edit': true},
    'bills': {'view': true, 'add': true, 'edit': true},
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final businesses = await Api.getBusinesses();
      final staff = await Api.getStaffUsers();
      if (!mounted) return;
      setState(() {
        _businesses =
            businesses.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _staff = staff.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
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
    super.dispose();
  }

  Future<void> _create() async {
    final username = _usernameController.text.trim();
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || name.isEmpty || password.length < 6) {
      setState(() {
        _error = 'Username and name are required. Password must be 6+ chars.';
      });
      return;
    }
    if (_selectedBusinesses.isEmpty) {
      setState(() {
        _error = 'Select at least one business access.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await Api.createStaffUser(
        username: username,
        name: name,
        password: password,
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        businessIds: _selectedBusinesses.toList(),
        permissions: _permissions,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User created successfully')),
      );
      _usernameController.clear();
      _nameController.clear();
      _phoneController.clear();
      _passwordController.clear();
      _selectedBusinesses.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create User')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: _phoneController,
                  decoration:
                      const InputDecoration(labelText: 'Phone (optional)'),
                ),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 16),
                const Text('Business Access',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ..._businesses.map((b) {
                  final id = (b['id'] as num).toInt();
                  final checked = _selectedBusinesses.contains(id);
                  return CheckboxListTile(
                    value: checked,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedBusinesses.add(id);
                        } else {
                          _selectedBusinesses.remove(id);
                        }
                      });
                    },
                    title: Text((b['name'] ?? '').toString()),
                  );
                }),
                const Divider(height: 24),
                const Text('Access Controls',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ..._permissions.entries.map((entry) {
                  final feature = entry.key;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(feature.toUpperCase(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Row(
                            children: [
                              _permToggle(feature, 'view'),
                              _permToggle(feature, 'add'),
                              _permToggle(feature, 'edit'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _saving ? null : _create,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Create User'),
                ),
                const SizedBox(height: 24),
                const Text('Created Users',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_staff.isEmpty)
                  const Text('No users yet.')
                else
                  ..._staff.map(
                    (u) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text((u['username'] ?? '').toString()),
                      subtitle: Text((u['name'] ?? '').toString()),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _permToggle(String feature, String key) {
    final value = _permissions[feature]?[key] ?? false;
    return Expanded(
      child: CheckboxListTile(
        value: value,
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(key),
        onChanged: (v) {
          setState(() {
            _permissions[feature]?[key] = v ?? false;
          });
        },
      ),
    );
  }
}
