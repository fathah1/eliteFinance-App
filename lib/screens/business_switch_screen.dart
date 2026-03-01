import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../access_control.dart';
import '../api.dart';
import 'add_business_screen.dart';

class BusinessSwitchScreen extends StatefulWidget {
  const BusinessSwitchScreen({super.key});

  @override
  State<BusinessSwitchScreen> createState() => _BusinessSwitchScreenState();
}

class _BusinessSwitchScreenState extends State<BusinessSwitchScreen> {
  List<Map<String, dynamic>> _businesses = [];
  bool _loading = true;
  String? _error;
  bool _isSuperUser = true;

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
      final user = await Api.getUser();
      if (!mounted) return;
      setState(() {
        _businesses = remote.cast<Map<String, dynamic>>();
        _isSuperUser = AccessControl.isSuperUser(user);
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
    final created = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddBusinessScreen(),
      ),
    );
    if (created == null || created['id'] == null) {
      await _load();
      return;
    }
    await _setActiveBusiness(
      (created['id'] as num).toInt(),
      (created['name'] ?? 'Business').toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF1E5EFF);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Businesses'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0C1434),
        elevation: 0,
      ),
      floatingActionButton: _isSuperUser
          ? FloatingActionButton(
              heroTag: 'business_add_fab',
              onPressed: _addBusiness,
              backgroundColor: brandBlue,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(12),
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
                  ),
                )
              : _businesses.isEmpty
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 18),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F1)),
                        ),
                        child: const Text(
                          'No businesses yet. Tap + to add your first business.',
                          style: TextStyle(color: Color(0xFF6D7486)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _businesses.length,
                      itemBuilder: (context, index) {
                        final b = _businesses[index];
                        final id = (b['id'] as num).toInt();
                        final name = (b['name'] ?? '').toString();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: const Color(0xFFE2E8F1)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x10000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            leading: const CircleAvatar(
                              radius: 18,
                              backgroundColor: Color(0xFFEAF0FF),
                              child: Icon(Icons.storefront_outlined,
                                  color: brandBlue),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0C1434),
                              ),
                            ),
                            subtitle: Text('Business ID: $id'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _setActiveBusiness(id, name),
                          ),
                        );
                      },
                    ),
    );
  }
}
