import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _activeBusinessServerId = prefs.getInt('active_business_server_id');
    _activeBusinessName = prefs.getString('active_business_name') ?? 'Business';

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

  void _buildListFromTransactions(
    List<dynamic> entities,
    List<dynamic> transactions,
  ) {
    final totals = <int, Map<String, double>>{};
    double creditTotal = 0;
    double debitTotal = 0;

    for (final t in transactions) {
      final cid = t['customer_id'] ?? t['supplier_id'];
      if (cid == null) continue;
      final id = cid as int;
      totals.putIfAbsent(id, () => {'credit': 0, 'debit': 0});
      final type = (t['type'] ?? '').toString();
      final amount = _asDouble(t['amount']);
      if (type == 'CREDIT') {
        totals[id]!['credit'] = totals[id]!['credit']! + amount;
        creditTotal += amount;
      } else {
        totals[id]!['debit'] = totals[id]!['debit']! + amount;
        debitTotal += amount;
      }
    }

    final enriched = entities.map<Map<String, dynamic>>((c) {
      final map = Map<String, dynamic>.from(c as Map);
      final opening = 0.0;
      final id = map['id'] as int;
      final credit = totals[id]?['credit'] ?? 0;
      final debit = totals[id]?['debit'] ?? 0;
      final balance = opening + credit - debit;
      return {
        ...map,
        'balance': balance,
      };
    }).toList();

    _items = enriched;
    _giveTotal = debitTotal;
    _getTotal = creditTotal;
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
    return Colors.grey;
  }

  String _balanceLabel(double balance) {
    final value = balance.abs().toStringAsFixed(2);
    return balance == 0 ? '0.00' : (balance > 0 ? '+$value' : '-$value');
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
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
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
            onPressed: () {
              Navigator.push(
                context,
                AppRoutes.onGenerateRoute(
                  const RouteSettings(name: AppRoutes.reports),
                ),
              );
            },
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
      floatingActionButton: FloatingActionButton.extended(
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
                        'mode':
                            _tab == 'customers' ? 'customers' : 'suppliers',
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
      ),
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
          Padding(
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
                              const Text('You will give'),
                              const SizedBox(height: 6),
                              Text(
                                'AED ${_giveTotal.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
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
                              const Text('You will get'),
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
                      Navigator.push(
                        context,
                        AppRoutes.onGenerateRoute(
                          const RouteSettings(name: AppRoutes.reports),
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
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: _tab == 'customers'
                          ? 'Search Customer'
                          : 'Search Supplier',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
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
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.filter_list),
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
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final c = _filtered[index];
                              final balance = _asDouble(c['balance']);
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.grey.shade200,
                                  child: Text(
                                    (c['name'] ?? 'A')
                                        .toString()
                                        .trim()
                                        .toUpperCase()
                                        .substring(0, 1),
                                    style: const TextStyle(color: Colors.black),
                                  ),
                                ),
                                title: Text((c['name'] ?? '').toString()),
                                subtitle: Text((c['phone'] ?? '').toString()),
                                trailing: Text(
                                  _balanceLabel(balance),
                                  style: TextStyle(
                                    color: _balanceColor(balance),
                                    fontWeight: FontWeight.bold,
                                  ),
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
