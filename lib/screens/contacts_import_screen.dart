import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
  final TextEditingController _searchController = TextEditingController();
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
          _error =
              'Contacts permission denied. Please enable access in Settings.';
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

  Future<String?> _saveContactPhoto(Contact c) async {
    final bytes = c.photo;
    if (bytes == null || bytes.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final safeId = c.id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final file = File('${dir.path}/contact_${widget.mode}_$safeId.jpg');
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }

  Future<void> _addContact(Contact c) async {
    final name = c.displayName.isEmpty ? 'Unnamed' : c.displayName;
    final phone = c.phones.isNotEmpty ? c.phones.first.number : null;
    final photoPath = await _saveContactPhoto(c);

    bool? saved;
    if (widget.mode == 'customers') {
      saved = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddCustomerScreen(
            initialName: name,
            initialPhone: phone,
            initialPhotoPath: photoPath,
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
            initialPhotoPath: photoPath,
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
      if (mounted) {
        setState(() => _loading = false);
      }
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    final title =
        widget.mode == 'customers' ? 'Select Customer' : 'Select Supplier';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_selectMode)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_selectedIds.length} selected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD8E0EC)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.mode == 'customers'
                      ? 'Search customer'
                      : 'Search supplier',
                  hintStyle:
                      const TextStyle(color: Color(0xFF8A93A5), fontSize: 16),
                  prefixIcon:
                      const Icon(Icons.search, color: brandBlue, size: 26),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _applyFilter();
                            });
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
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
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD8E0EC)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: brandBlue, width: 1.8),
                      ),
                      child: const Icon(Icons.add, color: brandBlue),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.mode == 'customers'
                          ? 'Add Customer'
                          : 'Add Supplier',
                      style: const TextStyle(
                        color: brandBlue,
                        fontSize: 18 / 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: brandBlue),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Row(
              children: [
                Text(
                  _selectMode ? 'Tap contacts to select multiple' : 'Contacts',
                  style: const TextStyle(
                    color: Color(0xFF7C8595),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
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
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
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
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundColor: brandBlue,
                                backgroundImage: c.photo != null
                                    ? MemoryImage(c.photo!)
                                    : null,
                                child: c.photo == null
                                    ? Text(
                                        initials.isNotEmpty ? initials : '?',
                                        style: const TextStyle(
                                            color: Colors.white),
                                      )
                                    : null,
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                phone,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF7B8494),
                                ),
                              ),
                              trailing: selected
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.green)
                                  : const Icon(Icons.chevron_right,
                                      color: Color(0xFF9AA3B2)),
                              onLongPress: () => _toggleSelect(c),
                              onTap: () async {
                                if (_selectMode) {
                                  _toggleSelect(c);
                                  return;
                                }
                                await _addContact(c);
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
