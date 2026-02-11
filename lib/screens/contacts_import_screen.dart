import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../routes.dart';
import 'add_customer_screen.dart';
import 'add_supplier_screen.dart';

class ContactsImportScreen extends StatefulWidget {
  final String mode; // customers | suppliers
  const ContactsImportScreen({super.key, required this.mode});

  @override
  State<ContactsImportScreen> createState() => _ContactsImportScreenState();
}

class _ContactsImportScreenState extends State<ContactsImportScreen> {
  List<Contact> _contacts = [];
  List<Contact> _filtered = [];
  bool _loading = true;
  String _query = '';
  String? _error;
  final Set<String> _selectedIds = {};
  bool _selectMode = false;

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

    final status = await Permission.contacts.status;
    if (!status.isGranted) {
      final req = await Permission.contacts.request();
      if (!req.isGranted) {
        setState(() {
          _loading = false;
          _error = 'Contacts permission denied. Please enable access in Settings.';
        });
        return;
      }
    }

    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: true,
    );

    setState(() {
      _contacts = contacts;
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    if (_query.isEmpty) {
      _filtered = _contacts;
      return;
    }
    final q = _query.toLowerCase();
    _filtered = _contacts.where((c) {
      final name = c.displayName.toLowerCase();
      final phones = c.phones.map((p) => p.number).join(' ').toLowerCase();
      return name.contains(q) || phones.contains(q);
    }).toList();
  }

  Future<int?> _getActiveBusinessServerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('active_business_server_id');
  }

  Future<void> _addContact(Contact c) async {
    final name = c.displayName.isEmpty ? 'Unnamed' : c.displayName;
    final phone = c.phones.isNotEmpty ? c.phones.first.number : null;

    bool? saved;
    if (widget.mode == 'customers') {
      saved = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddCustomerScreen(
            initialName: name,
            initialPhone: phone,
          ),
        ),
      );
    } else {
      saved = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddSupplierScreen(
            initialName: name,
            initialPhone: phone,
          ),
        ),
      );
    }
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $name')),
      );
    }
  }

  Future<void> _bulkImport() async {
    if (_selectedIds.isEmpty) return;
    setState(() => _loading = true);
    try {
      for (final c in _contacts) {
        if (_selectedIds.contains(c.id)) {
          await _addContact(c);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${_selectedIds.length}')),
      );
      setState(() {
        _selectedIds.clear();
        _selectMode = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _toggleSelect(Contact c) {
    setState(() {
      _selectMode = true;
      if (_selectedIds.contains(c.id)) {
        _selectedIds.remove(c.id);
      } else {
        _selectedIds.add(c.id);
      }
      if (_selectedIds.isEmpty) _selectMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    final title = widget.mode == 'customers'
        ? 'Select Customer'
        : 'Select Supplier';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_selectMode)
            TextButton(
              onPressed: _bulkImport,
              child: const Text(
                'IMPORT',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: widget.mode == 'customers'
                    ? 'Customer name'
                    : 'Supplier name',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _query = '';
                      _applyFilter();
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: brandBlue),
                ),
              ),
              onChanged: (v) {
                setState(() {
                  _query = v.trim();
                  _applyFilter();
                });
              },
            ),
          ),
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: brandBlue, width: 2),
              ),
              child: const Icon(Icons.add, color: brandBlue),
            ),
            title: Text(
              widget.mode == 'customers' ? 'Add Customer' : 'Add Supplier',
              style: const TextStyle(color: brandBlue),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              if (widget.mode == 'customers') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddCustomerScreen(),
                  ),
                );
              } else {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddSupplierScreen(),
                  ),
                );
              }
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () async {
                                await openAppSettings();
                                await _load();
                              },
                              child: const Text('Open Settings'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final c = _filtered[index];
                          final name = c.displayName.isNotEmpty
                              ? c.displayName
                              : 'Unnamed';
                          final phone =
                              c.phones.isNotEmpty ? c.phones.first.number : '';
                          final initials = name
                              .split(' ')
                              .where((p) => p.isNotEmpty)
                              .take(2)
                              .map((p) => p[0].toUpperCase())
                              .join();
                          final selected = _selectedIds.contains(c.id);
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundColor: brandBlue,
                              backgroundImage:
                                  c.photo != null ? MemoryImage(c.photo!) : null,
                              child: c.photo == null
                                  ? Text(
                                      initials.isNotEmpty ? initials : '?',
                                      style:
                                          const TextStyle(color: Colors.white),
                                    )
                                  : null,
                            ),
                            title: Text(name),
                            subtitle: Text(phone),
                            trailing: selected
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green)
                                : null,
                            onLongPress: () => _toggleSelect(c),
                            onTap: () async {
                              if (_selectMode) {
                                _toggleSelect(c);
                                return;
                              }
                              await _addContact(c);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
