import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../access_control.dart';
import '../api.dart';
import '../routes.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _query = '';
  int? _activeBusinessServerId;
  String _activeBusinessName = 'Business';
  String _tab = 'customers';
  double _giveTotal = 0;
  double _getTotal = 0;
  final Map<int, DateTime> _dueMap = {};
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _activeBusinessServerId = prefs.getInt('active_business_server_id');
    _activeBusinessName = prefs.getString('active_business_name') ?? 'Business';
    _user = await Api.getUser();

    if (_activeBusinessServerId == null) {
      await _autoSelectBusiness();
    }

    await _loadData();
  }

  Future<void> _autoSelectBusiness() async {
    try {
      final businesses = await Api.getBusinesses();
      if (businesses.isEmpty) return;
      final first = businesses.first as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('active_business_server_id', first['id'] as int);
      await prefs.setString('active_business_name', first['name'] as String);
      _activeBusinessServerId = first['id'] as int;
      _activeBusinessName = first['name'] as String;
    } catch (_) {
      // ignore
    }
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> _loadData() async {
    if (_activeBusinessServerId == null) {
      setState(() {
        _items = [];
        _filtered = [];
        _loading = false;
        _giveTotal = 0;
        _getTotal = 0;
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _loadDueDates();
      if (_tab == 'customers') {
        final customers = await Api.getCustomers(
          businessId: _activeBusinessServerId!,
        );
        final transactions = await Api.getAllTransactions(
          businessId: _activeBusinessServerId!,
        );
        _buildListFromTransactions(customers, transactions);
      } else {
        final suppliers = await Api.getSuppliers(
          businessId: _activeBusinessServerId!,
        );
        final transactions = await Api.getAllSupplierTransactions(
          businessId: _activeBusinessServerId!,
        );
        _buildListFromTransactions(suppliers, transactions);
      }

      if (!mounted) return;
      setState(() {
        _applyFilter();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _filtered = [];
        _loading = false;
        _giveTotal = 0;
        _getTotal = 0;
      });
    }
  }

  Future<void> _loadDueDates() async {
    final prefs = await SharedPreferences.getInstance();
    _dueMap.clear();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (_tab == 'customers' && key.startsWith('customer_due_')) {
        final id = int.tryParse(key.replaceFirst('customer_due_', ''));
        if (id == null) continue;
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        final dt = DateTime.tryParse(raw);
        if (dt != null) _dueMap[id] = dt;
      }
      if (_tab == 'suppliers' && key.startsWith('supplier_due_')) {
        final id = int.tryParse(key.replaceFirst('supplier_due_', ''));
        if (id == null) continue;
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        final dt = DateTime.tryParse(raw);
        if (dt != null) _dueMap[id] = dt;
      }
    }
  }

  String _dueChipLabel(DateTime due) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due.year, due.month, due.day);
    if (day == today) return 'Due today';
    if (day.isBefore(today)) return 'Overdue';
    return DateFormat('dd MMM').format(day);
  }

  void _buildListFromTransactions(
    List<dynamic> entities,
    List<dynamic> transactions,
  ) {
    final totals = <int, Map<String, double>>{};
    final latest = <int, DateTime>{};
    double creditTotal = 0;
    double debitTotal = 0;

    for (final t in transactions) {
      final cid = t['customer_id'] ?? t['supplier_id'];
      if (cid == null) continue;
      final id = cid as int;
      totals.putIfAbsent(id, () => {'credit': 0, 'debit': 0});
      final type = (t['type'] ?? '').toString();
      final amount = _asDouble(t['amount']);
      final raw = (t['created_at'] ?? '').toString();
      final dt = DateTime.tryParse(raw);
      if (dt != null) {
        final prev = latest[id];
        if (prev == null || dt.isAfter(prev)) latest[id] = dt;
      }
      if (type == 'CREDIT') {
        totals[id]!['credit'] = totals[id]!['credit']! + amount;
        creditTotal += amount;
      } else {
        totals[id]!['debit'] = totals[id]!['debit']! + amount;
        debitTotal += amount;
      }
    }

    double sumPositive = 0;
    double sumNegative = 0;
    final enriched = entities.map<Map<String, dynamic>>((c) {
      final map = Map<String, dynamic>.from(c as Map);
      final opening = 0.0;
      final id = map['id'] as int;
      final credit = totals[id]?['credit'] ?? 0;
      final debit = totals[id]?['debit'] ?? 0;
      final balance = opening + credit - debit;
      final last = latest[id];
      if (balance > 0) {
        sumPositive += balance;
      } else if (balance < 0) {
        sumNegative += balance.abs();
      }
      return {
        ...map,
        'balance': balance,
        'last_tx': last?.toIso8601String(),
      };
    }).toList();

    enriched.sort((a, b) {
      final at = a['last_tx'] as String?;
      final bt = b['last_tx'] as String?;
      if (at != null && bt != null) {
        return bt.compareTo(at);
      }
      if (at != null) return -1;
      if (bt != null) return 1;
      final an = (a['name'] ?? '').toString().toLowerCase();
      final bn = (b['name'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });

    _items = enriched;
    // Sum of red (positive) balances = you will get
    // Sum of green (negative) balances = you will give
    _getTotal = sumPositive;
    _giveTotal = sumNegative;
  }

  void _applyFilter() {
    if (_query.isEmpty) {
      _filtered = _items;
      return;
    }
    final q = _query.toLowerCase();
    _filtered = _items.where((c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      final phone = (c['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  Color _balanceColor(double balance) {
    if (balance > 0) return Colors.red;
    if (balance < 0) return Colors.green;
    return Colors.black;
  }

  String _balanceLabel(double balance) {
    final value = balance.abs().toStringAsFixed(0);
    return balance == 0 ? '0' : 'AED $value';
  }

  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final dtUtc = dt.isUtc ? dt : dt.toUtc();
    var diff = DateTime.now().toUtc().difference(dtUtc);
    if (diff.isNegative) diff = diff.abs();
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) return '${weeks} weeks ago';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '${months} months ago';
    final years = (diff.inDays / 365).floor();
    return '${years} years ago';
  }

  String _paymentMessage(String name, String? phone, double amount) {
    final safePhone = (phone ?? '').trim();
    final amountLabel = amount.abs().toStringAsFixed(0);
    final contact = safePhone.isEmpty ? name : '$name ($safePhone)';
    return '$contact has requested a payment of AED $amountLabel.';
  }

  Widget _buildRequestCard(
    String name,
    String? phone,
    double amount,
  ) {
    final time = DateFormat('hh:mm a dd MMM yyyy').format(DateTime.now());
    final amountLabel = amount.abs().toStringAsFixed(0);
    const appName = 'app';
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFE9EEF9),
              child: Text(
                name.trim().isEmpty
                    ? 'C'
                    : name.trim().toUpperCase().substring(0, 1),
                style: const TextStyle(
                  color: Color(0xFF0B4F9E),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              name.isEmpty ? 'Customer' : name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (phone != null && phone.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  phone,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              'Requested at $time',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Text(
              'AED $amountLabel',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            const Text(
              appName,
              style: TextStyle(
                color: Color(0xFFB0182E),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareOnWhatsApp(
    String name,
    String? phone,
    double amount,
  ) async {
    final user = await Api.getUser();
    final userName = (user?['username'] ?? 'User').toString();
    final userPhone =
        user?['phone'] == null ? null : (user?['phone'] ?? '').toString();
    final controller = ScreenshotController();
    final mediaQuery = MediaQueryData(
      size: const Size(360, 640),
      devicePixelRatio: 2.0,
      textScaler: TextScaler.linear(1),
    );
    final widget = MediaQuery(
      data: mediaQuery,
      child: Directionality(
        textDirection: ui.TextDirection.ltr,
        child: Container(
          color: Colors.white,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: _buildRequestCard(userName, userPhone, amount),
        ),
      ),
    );
    final Uint8List imageBytes = await controller.captureFromWidget(
      widget,
      pixelRatio: 2.0,
    );
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/payment_request_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(imageBytes);
    final message = _paymentMessage(userName, userPhone, amount);
    await Share.shareXFiles([XFile(file.path)], text: message);
  }

  Future<void> _sendSms(
    String name,
    String? phone,
    double amount,
  ) async {
    final user = await Api.getUser();
    final userName = (user?['username'] ?? 'User').toString();
    final userPhone =
        user?['phone'] == null ? '' : (user?['phone'] ?? '').toString();
    final number = userPhone.trim();
    if (number.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number found.')),
      );
      return;
    }
    final message =
        Uri.encodeComponent(_paymentMessage(userName, userPhone, amount));
    final uri = Uri.parse('sms:$number?body=$message');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showRemindSheet(
    String name,
    String? phone,
    double amount,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final amountLabel = amount.abs().toStringAsFixed(0);
        final viewPadding = MediaQuery.of(context).viewPadding;
        final bottomInset = viewPadding.bottom > 0 ? viewPadding.bottom : 8.0;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Request ${name.isEmpty ? 'customer' : name} to pay you',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'AED $amountLabel',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _sendSms(name, phone, amount),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B4F9E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.sms),
                        label: const Text('SMS'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _shareOnWhatsApp(name, phone, amount),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DAA61),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const FaIcon(FontAwesomeIcons.whatsapp),
                        label: const Text('WHATSAPP'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openBusinesses() async {
    final changed = await Navigator.push(
      context,
      AppRoutes.onGenerateRoute(
        const RouteSettings(name: AppRoutes.businesses),
      ),
    );
    if (changed == true) {
      final prefs = await SharedPreferences.getInstance();
      _activeBusinessServerId = prefs.getInt('active_business_server_id');
      _activeBusinessName =
          prefs.getString('active_business_name') ?? 'Business';
      await _loadData();
    }
  }

  Widget _tabButton(String label, String value) {
    final selected = _tab == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (_tab == value) return;
          setState(() {
            _tab = value;
          });
          _loadData();
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ),
            Container(
              height: 2,
              color: selected ? const Color(0xFFF9A825) : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    final canAddParties = AccessControl.canAdd(_user, 'parties');
    final canViewReports = AccessControl.canView(_user, 'reports');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Text(_activeBusinessName),
            const SizedBox(width: 6),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.store_mall_directory),
            onPressed: _openBusinesses,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: canViewReports
                ? () {
                    Navigator.push(
                      context,
                      AppRoutes.onGenerateRoute(
                        const RouteSettings(name: AppRoutes.reports),
                      ),
                    );
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                AppRoutes.onGenerateRoute(
                  const RouteSettings(name: AppRoutes.settings),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: canAddParties
          ? FloatingActionButton.extended(
              heroTag: 'home_add_customer_fab',
              backgroundColor: const Color(0xFFA0004A),
              foregroundColor: Colors.white,
              onPressed: _activeBusinessServerId == null
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        AppRoutes.onGenerateRoute(
                          RouteSettings(
                            name: AppRoutes.contactsImport,
                            arguments: {
                              'mode': _tab == 'customers'
                                  ? 'customers'
                                  : 'suppliers',
                            },
                          ),
                        ),
                      );
                      _loadData();
                    },
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: Text(
                _tab == 'customers' ? 'ADD CUSTOMER' : 'ADD SUPPLIER',
              ),
            )
          : null,
      body: Column(
        children: [
          Container(
            color: brandBlue,
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _tabButton('CUSTOMERS', 'customers'),
                _tabButton('SUPPLIERS', 'suppliers'),
              ],
            ),
          ),
          Container(
            color: brandBlue,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('You will give',
                                  style: TextStyle(color: Colors.black)),
                              const SizedBox(height: 6),
                              Text(
                                'AED ${_giveTotal.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: Colors.grey.shade300,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('You will get',
                                  style: TextStyle(color: Colors.black)),
                              const SizedBox(height: 6),
                              Text(
                                'AED ${_getTotal.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  InkWell(
                    onTap: () {
                      final initialTab =
                          _tab == 'suppliers' ? 'Supplier' : 'Customer';
                      Navigator.push(
                        context,
                        AppRoutes.onGenerateRoute(
                          RouteSettings(
                            name: AppRoutes.reports,
                            arguments: {'initialTab': initialTab},
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.picture_as_pdf, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'View Reports',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: _tab == 'customers'
                          ? 'Search customer'
                          : 'Search supplier',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFFF5F6FA),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
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
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F6FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.tune),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _activeBusinessServerId == null
                    ? const Center(
                        child: Text('Select a business to continue.'))
                    : _filtered.isEmpty
                        ? const Center(child: Text('No entries yet.'))
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final c = _filtered[index];
                              final balance = _asDouble(c['balance']);
                              final id = c['id'] as int?;
                              final due = id != null ? _dueMap[id] : null;
                              return ListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFFE9EEF9),
                                  child: Text(
                                    (c['name'] ?? 'A')
                                        .toString()
                                        .trim()
                                        .toUpperCase()
                                        .substring(0, 1),
                                    style: const TextStyle(
                                      color: Color(0xFF0B4F9E),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                title: Text((c['name'] ?? '').toString()),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _timeAgo(c['last_tx'] as String?) != ''
                                          ? _timeAgo(c['last_tx'] as String?)
                                          : (c['phone'] ?? '').toString(),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    if (due != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFDEDED),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _dueChipLabel(due),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.red,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _balanceLabel(balance),
                                      style: TextStyle(
                                        color: _balanceColor(balance),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    if (balance > 0)
                                      TextButton(
                                        onPressed: () {
                                          final name =
                                              (c['name'] ?? '').toString();
                                          final phone = c['phone'] == null
                                              ? null
                                              : (c['phone'] ?? '').toString();
                                          _showRemindSheet(
                                              name, phone, balance);
                                        },
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(0, 20),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          'REMIND',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    AppRoutes.onGenerateRoute(
                                      RouteSettings(
                                        name: _tab == 'customers'
                                            ? AppRoutes.customerLedger
                                            : AppRoutes.supplierLedger,
                                        arguments: c,
                                      ),
                                    ),
                                  ).then((_) => _loadData());
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
