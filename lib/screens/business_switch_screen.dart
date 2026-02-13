import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';

class BusinessSwitchScreen extends StatefulWidget {
  const BusinessSwitchScreen({super.key});

  @override
  State<BusinessSwitchScreen> createState() => _BusinessSwitchScreenState();
}

class _BusinessSwitchScreenState extends State<BusinessSwitchScreen> {
  List<Map<String, dynamic>> _businesses = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final remote = await Api.getBusinesses();
      if (!mounted) return;
      setState(() {
        _businesses = remote.cast<Map<String, dynamic>>();
        _loading = false;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setActiveBusiness(int serverId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_business_server_id', serverId);
    await prefs.setString('active_business_name', name);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _addBusiness() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Business'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Business name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      final created = await Api.createBusiness(name: name);
      if (created['id'] != null) {
        await _setActiveBusiness(created['id'] as int, created['name'] as String);
        return;
      }
    } catch (_) {
      // ignore
    }

    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Businesses')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'business_add_fab',
        onPressed: _addBusiness,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _businesses.isEmpty
                  ? const Center(child: Text('No businesses yet.'))
                  : ListView.separated(
                      itemCount: _businesses.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final b = _businesses[index];
                        final name = (b['name'] ?? '').toString();
                        return ListTile(
                          title: Text(name),
                          onTap: () =>
                              _setActiveBusiness(b['id'] as int, name),
                        );
                      },
                    ),
    );
  }
}
