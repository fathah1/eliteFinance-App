import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../api.dart';
import '../access_control.dart';
import '../db.dart';
import '../offline_sync_service.dart';
import '../routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _backupBusy = false;
  String? _backupStatus;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await Api.getUser();
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await Api.clearToken();
    await Api.clearUser();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      AppRoutes.onGenerateRoute(
        const RouteSettings(name: AppRoutes.login),
      ),
      (route) => false,
    );
  }

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  void _collectImageUrls(dynamic value, Set<String> refs,
      {String keyHint = ''}) {
    if (value == null) return;
    if (value is Map) {
      value.forEach((k, v) {
        _collectImageUrls(v, refs, keyHint: k.toString());
      });
      return;
    }
    if (value is List) {
      for (final v in value) {
        _collectImageUrls(v, refs, keyHint: keyHint);
      }
      return;
    }
    if (value is! String) return;
    final raw = value.trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return;

    final key = keyHint.toLowerCase();
    final keyLooksMedia = key.contains('photo') ||
        key.contains('image') ||
        key.contains('attachment') ||
        key.contains('url') ||
        key.contains('path');

    // Keep local file paths as-is (attachments selected on device).
    final rawFile = raw.startsWith('file://') ? raw.substring(7) : raw;
    if (rawFile.startsWith('/')) {
      final f = File(rawFile);
      if (f.existsSync()) {
        refs.add('file://$rawFile');
        return;
      }
    }

    if (!keyLooksMedia && !raw.startsWith('http')) return;
    final resolved = Api.resolveMediaUrl(raw);
    if (resolved == null || resolved.isEmpty) return;
    if (_isImageUrl(resolved)) {
      refs.add(resolved);
    }
  }

  Future<Map<String, dynamic>> _buildBackupPayload() async {
    final user = await Api.getUser();
    final businessesRaw = await Api.getBusinesses();
    final businesses =
        businessesRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final byBusiness = <String, dynamic>{};
    for (final b in businesses) {
      final businessId = ((b['id'] is num)
              ? (b['id'] as num).toInt()
              : int.tryParse((b['id'] ?? '').toString())) ??
          0;
      if (businessId <= 0) continue;

      final customers = await Api.getCustomers(businessId: businessId);
      final suppliers = await Api.getSuppliers(businessId: businessId);
      final customerTx = await Api.getAllTransactions(businessId: businessId);
      final supplierTx =
          await Api.getAllSupplierTransactions(businessId: businessId);
      final products =
          await Api.getItems(businessId: businessId, type: 'product');
      final sales = await Api.getSales(businessId: businessId);
      final purchases = await Api.getPurchases(businessId: businessId);
      final expenses = await Api.getExpenses(businessId: businessId);

      byBusiness[businessId.toString()] = {
        'business': b,
        'customers': customers,
        'suppliers': suppliers,
        'customer_transactions': customerTx,
        'supplier_transactions': supplierTx,
        'items': products,
        'sales': sales,
        'purchases': purchases,
        'expenses': expenses,
      };
    }

    return {
      'app': 'ECBooks',
      'generated_at': DateTime.now().toIso8601String(),
      'user': user,
      'businesses': businesses,
      'data_by_business': byBusiness,
    };
  }

  Future<void> _manualBackupAndSync() async {
    if (_backupBusy) return;
    setState(() {
      _backupBusy = true;
      _backupStatus = 'Syncing data...';
    });

    try {
      await OfflineSyncService.instance.syncPendingNow();
      await OfflineSyncService.instance.refreshStatus();

      setState(() => _backupStatus = 'Collecting data...');
      final payload = await _buildBackupPayload();

      final docsDir = await getApplicationDocumentsDirectory();
      final rootDir = Directory(p.join(docsDir.path, 'ECBooks', 'backups'));
      await rootDir.create(recursive: true);

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final workDir = Directory(p.join(rootDir.path, 'backup_$stamp'));
      await workDir.create(recursive: true);

      final jsonFile = File(p.join(workDir.path, 'backup.json'));
      await jsonFile
          .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));

      setState(() => _backupStatus = 'Copying local database...');
      final dbPath = p.join(await getDatabasesPath(), 'khata.db');
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.copy(p.join(workDir.path, 'khata.db'));
      }

      final imageRefs = <String>{};
      _collectImageUrls(payload, imageRefs);

      setState(() => _backupStatus = 'Backing up images...');
      final imagesDir = Directory(p.join(workDir.path, 'images'));
      await imagesDir.create(recursive: true);
      var imageSavedCount = 0;
      var idx = 0;
      for (final ref in imageRefs) {
        idx++;
        try {
          final target = File(p.join(imagesDir.path,
              '${idx}_${DateTime.now().millisecondsSinceEpoch}.jpg'));
          if (ref.startsWith('file://')) {
            final localPath = ref.substring(7);
            final localFile = File(localPath);
            if (!await localFile.exists()) continue;
            final bytes = await localFile.readAsBytes();
            if (bytes.isEmpty) continue;
            await target.writeAsBytes(bytes, flush: true);
          } else {
            http.Response? res;
            for (var i = 0; i < 2; i++) {
              try {
                final r = await http
                    .get(Uri.parse(ref))
                    .timeout(const Duration(seconds: 12));
                if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
                  res = r;
                  break;
                }
              } catch (_) {}
            }
            if (res == null) continue;
            final uri = Uri.parse(ref);
            final baseName = p.basename(uri.path).isEmpty
                ? 'img_$idx.jpg'
                : p.basename(uri.path);
            final namedTarget =
                File(p.join(imagesDir.path, '${idx}_$baseName'));
            await namedTarget.writeAsBytes(res.bodyBytes, flush: true);
          }
          imageSavedCount++;
        } catch (_) {
          // Ignore failing image URLs and continue backup.
        }
      }

      setState(() => _backupStatus = 'Creating backup file...');
      final zipPath = p.join(rootDir.path, 'ecbooks_backup_$stamp.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      encoder.addDirectory(workDir);
      encoder.close();

      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }

      if (!mounted) return;
      setState(() => _backupStatus = 'Backup completed');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup completed'),
          content: Text(
            'Backup saved to:\n$zipPath\n\n'
            'Images backed up: $imageSavedCount / ${imageRefs.length}',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await OpenFilex.open(zipPath);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Open'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _backupStatus = 'Backup failed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _backupBusy = false;
        });
      }
    }
  }

  Future<File?> _pickBackupZip() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final rootDir = Directory(p.join(docsDir.path, 'ECBooks', 'backups'));
    if (!await rootDir.exists()) return null;

    final files = rootDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.zip'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (files.isEmpty) return null;

    if (!mounted) return null;
    return showModalBottomSheet<File>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Select Backup File',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (_, i) {
                  final file = files[i];
                  final modified = file.lastModifiedSync();
                  return ListTile(
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: Text(p.basename(file.path)),
                    subtitle: Text(
                      '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} '
                      '${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}',
                    ),
                    onTap: () => Navigator.pop(ctx, file),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<File?> _findFileRecursive(Directory root, String fileName) async {
    await for (final ent in root.list(recursive: true, followLinks: false)) {
      if (ent is File &&
          p.basename(ent.path).toLowerCase() == fileName.toLowerCase()) {
        return ent;
      }
    }
    return null;
  }

  Future<void> _restoreCacheFromPayload(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();

    final businessesRaw = payload['businesses'];
    final businesses = businessesRaw is List ? businessesRaw : const [];
    await prefs.setString('cache_businesses', jsonEncode(businesses));

    final dataByBusinessRaw = payload['data_by_business'];
    if (dataByBusinessRaw is Map) {
      for (final entry in dataByBusinessRaw.entries) {
        final keyBusinessId = int.tryParse(entry.key.toString());
        final data = entry.value;
        if (data is! Map) continue;
        final map = Map<String, dynamic>.from(data);
        final businessMap = (map['business'] is Map)
            ? Map<String, dynamic>.from(map['business'] as Map)
            : <String, dynamic>{};
        final businessId = ((businessMap['id'] is num)
                ? (businessMap['id'] as num).toInt()
                : int.tryParse((businessMap['id'] ?? '').toString())) ??
            keyBusinessId;
        if (businessId == null || businessId <= 0) continue;

        final customers =
            map['customers'] is List ? map['customers'] : const [];
        final suppliers =
            map['suppliers'] is List ? map['suppliers'] : const [];
        final tx = map['customer_transactions'] is List
            ? map['customer_transactions']
            : const [];
        final supplierTx = map['supplier_transactions'] is List
            ? map['supplier_transactions']
            : const [];
        final items = map['items'] is List ? map['items'] : const [];
        final sales = map['sales'] is List ? map['sales'] : const [];
        final purchases =
            map['purchases'] is List ? map['purchases'] : const [];
        final expenses = map['expenses'] is List ? map['expenses'] : const [];

        await prefs.setString(
            'cache_customers_b_$businessId', jsonEncode(customers));
        await prefs.setString(
            'cache_suppliers_b_$businessId', jsonEncode(suppliers));
        await prefs.setString(
            'cache_transactions_b_$businessId', jsonEncode(tx));
        await prefs.setString('cache_supplier_transactions_b_$businessId',
            jsonEncode(supplierTx));
        await prefs.setString(
            'cache_items_b_${businessId}_t_product', jsonEncode(items));
        await prefs.setString('cache_sales_b_$businessId', jsonEncode(sales));
        await prefs.setString(
            'cache_purchases_b_$businessId', jsonEncode(purchases));
        await prefs.setString(
            'cache_expenses_b_$businessId', jsonEncode(expenses));
      }
    }
  }

  Future<void> _restoreFromBackup() async {
    if (_backupBusy) return;

    final zipFile = await _pickBackupZip();
    if (zipFile == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No backup zip found in ECBooks/backups')),
      );
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore backup'),
            content: Text(
              'Restore from:\n${p.basename(zipFile.path)}\n\n'
              'This will replace local offline data with backup data.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Restore'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    setState(() {
      _backupBusy = true;
      _backupStatus = 'Restoring backup...';
    });

    Directory? tempDir;
    try {
      final tempRoot = await getTemporaryDirectory();
      tempDir = Directory(
        p.join(tempRoot.path,
            'ecbooks_restore_${DateTime.now().millisecondsSinceEpoch}'),
      );
      await tempDir.create(recursive: true);

      setState(() => _backupStatus = 'Extracting zip...');
      final input = InputFileStream(zipFile.path);
      final archive = ZipDecoder().decodeBuffer(input);
      extractArchiveToDisk(archive, tempDir.path);
      input.close();

      setState(() => _backupStatus = 'Reading backup files...');
      final backupJsonFile = await _findFileRecursive(tempDir, 'backup.json');
      final backupDbFile = await _findFileRecursive(tempDir, 'khata.db');
      if (backupJsonFile == null) {
        throw Exception('backup.json not found in zip');
      }

      final payload = jsonDecode(await backupJsonFile.readAsString());
      if (payload is! Map) {
        throw Exception('Invalid backup.json');
      }
      await _restoreCacheFromPayload(Map<String, dynamic>.from(payload));

      if (backupDbFile != null) {
        setState(() => _backupStatus = 'Restoring local database...');
        await Db.instance.close();
        final dbPath = p.join(await getDatabasesPath(), 'khata.db');
        final dbFile = File(dbPath);
        await dbFile.parent.create(recursive: true);
        if (await dbFile.exists()) {
          await dbFile.delete();
        }
        await backupDbFile.copy(dbPath);
      }

      setState(() => _backupStatus = 'Refreshing app cache...');
      await OfflineSyncService.instance.refreshStatus();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore completed'),
          content: const Text(
            'Backup restored successfully.\n\n'
            'Please close and reopen the app once to reload all screens.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      setState(() => _backupStatus = 'Restore completed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _backupStatus = 'Restore failed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e')),
      );
    } finally {
      try {
        if (tempDir != null && await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _backupBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF1E5EFF);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0C1434),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
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
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 22,
                        backgroundColor: Color(0xFFEAF0FF),
                        child: Icon(Icons.person_outline, color: brandBlue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Signed in as',
                              style: TextStyle(color: Color(0xFF6D7486)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (_user?['username'] ?? 'Unknown').toString(),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0C1434),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
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
                    children: [
                      _settingItem(
                        icon: Icons.backup_outlined,
                        title: 'Backup',
                        subtitle: _backupBusy
                            ? (_backupStatus ?? 'Running...')
                            : (_backupStatus ??
                                'Manual sync + backup (data and images)'),
                        onTap: _manualBackupAndSync,
                      ),
                      _divider(),
                      _settingItem(
                        icon: Icons.restore_page_outlined,
                        title: 'Restore',
                        subtitle: _backupBusy
                            ? (_backupStatus ?? 'Running...')
                            : 'Restore local data from backup zip',
                        onTap: _restoreFromBackup,
                      ),
                      _divider(),
                      _settingItem(
                        icon: Icons.language_outlined,
                        title: 'Language',
                        subtitle: 'English',
                      ),
                      _divider(),
                      _settingItem(
                        icon: Icons.currency_exchange,
                        title: 'Currency',
                        subtitle: 'AED',
                      ),
                      _divider(),
                      _settingItem(
                        icon: Icons.lock_outline,
                        title: 'App Lock',
                        subtitle: 'Disabled',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (AccessControl.isSuperUser(_user))
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F1)),
                    ),
                    child: _settingItem(
                      icon: Icons.group_add_outlined,
                      title: 'Create User',
                      subtitle: 'Add sub users and assign access controls',
                      onTap: () {
                        Navigator.push(
                          context,
                          AppRoutes.onGenerateRoute(
                            const RouteSettings(name: AppRoutes.createUser),
                          ),
                        );
                      },
                    ),
                  ),
                if (AccessControl.isSuperUser(_user))
                  const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F1)),
                  ),
                  child: _settingItem(
                    icon: Icons.logout,
                    title: 'Logout',
                    subtitle: 'Sign out from this device',
                    iconColor: const Color(0xFFC6284D),
                    onTap: _logout,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 60, endIndent: 16);

  Widget _settingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    Color iconColor = const Color(0xFF1E5EFF),
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xFFEAF0FF),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF0C1434),
        ),
      ),
      subtitle: Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
