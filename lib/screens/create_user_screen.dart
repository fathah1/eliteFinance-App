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
    const brandBlue = Color(0xFF1E5EFF);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Create User'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0C1434),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                _sectionCard(
                  title: 'User Details',
                  child: Column(
                    children: [
                      _inputField(
                        controller: _usernameController,
                        hint: 'Username',
                        icon: Icons.alternate_email,
                      ),
                      const SizedBox(height: 10),
                      _inputField(
                        controller: _nameController,
                        hint: 'Name',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 10),
                      _inputField(
                        controller: _phoneController,
                        hint: 'Phone (optional)',
                        icon: Icons.phone_outlined,
                      ),
                      const SizedBox(height: 10),
                      _inputField(
                        controller: _passwordController,
                        hint: 'Password',
                        icon: Icons.lock_outline,
                        obscure: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'Business Access',
                  child: Column(
                    children: _businesses.map((b) {
                      final id = (b['id'] as num).toInt();
                      final checked = _selectedBusinesses.contains(id);
                      return CheckboxListTile(
                        value: checked,
                        activeColor: brandBlue,
                        contentPadding: EdgeInsets.zero,
                        title: Text((b['name'] ?? '').toString()),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedBusinesses.add(id);
                            } else {
                              _selectedBusinesses.remove(id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'Access Controls',
                  child: Column(
                    children: _permissions.entries.map((entry) {
                      final feature = entry.key;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFFF8FAFE),
                          border: Border.all(color: const Color(0xFFE2E8F1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              feature.toUpperCase(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0C1434)),
                            ),
                            Row(
                              children: [
                                _permToggle(feature, 'view'),
                                _permToggle(feature, 'add'),
                                _permToggle(feature, 'edit'),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _create,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E5EFF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF9CB8FF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Create User',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                _sectionCard(
                  title: 'Created Users',
                  child: _staff.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No users yet.'),
                        )
                      : Column(
                          children: _staff.map((u) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                radius: 16,
                                backgroundColor: Color(0xFFEAF0FF),
                                child: Icon(Icons.person_outline,
                                    size: 18, color: brandBlue),
                              ),
                              title: Text((u['username'] ?? '').toString()),
                              subtitle: Text((u['name'] ?? '').toString()),
                            );
                          }).toList(),
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
        activeColor: const Color(0xFF1E5EFF),
        title: Text(key),
        onChanged: (v) {
          setState(() {
            _permissions[feature]?[key] = v ?? false;
          });
        },
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0C1434),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
