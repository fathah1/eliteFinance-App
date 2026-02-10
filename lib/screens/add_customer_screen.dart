import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _openingController = TextEditingController();
  String? _error;
  bool _loading = false;

  Future<int?> _getActiveBusinessServerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('active_business_server_id');
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() {
        _error = 'Name is required.';
      });
      return;
    }

    final businessId = await _getActiveBusinessServerId();
    if (businessId == null) {
      setState(() {
        _error = 'Please select a business first.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final opening = double.tryParse(_openingController.text.trim()) ?? 0;
    try {
      await Api.createCustomer(
        businessId: businessId,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        openingBalance: opening,
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Customer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: _openingController,
              decoration:
                  const InputDecoration(labelText: 'Opening balance (optional)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
