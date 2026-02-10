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
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _query = '';
  int? _activeBusinessServerId;
  String _activeBusinessName = 'Business';

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

    debugPrint('Active business server id: $_activeBusinessServerId');
    debugPrint('Active business name: $_activeBusinessName');

    await _loadCustomers();
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

  Future<void> _loadCustomers() async {
    if (_activeBusinessServerId == null) {
      setState(() {
        _customers = [];
        _filtered = [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
    });

    try {
      final customers = await Api.getCustomers(
        businessId: _activeBusinessServerId!,
      );

      debugPrint('customers: $customers}');

      final transactions = await Api.getAllTransactions(
        businessId: _activeBusinessServerId!,
      );

      final totals = <int, Map<String, double>>{};
      for (final t in transactions) {
        final cid = t['customer_id'] as int;
        totals.putIfAbsent(cid, () => {'credit': 0, 'debit': 0});
        final type = (t['type'] ?? '').toString();
        final amount = (t['amount'] as num?)?.toDouble() ?? 0;
        if (type == 'CREDIT') {
          totals[cid]!['credit'] = totals[cid]!['credit']! + amount;
        } else {
          totals[cid]!['debit'] = totals[cid]!['debit']! + amount;
        }
      }

      final enriched = customers.map((c) {
        final opening = (c['opening_balance'] as num?)?.toDouble() ?? 0;
        final id = c['id'] as int;
        final credit = totals[id]?['credit'] ?? 0;
        final debit = totals[id]?['debit'] ?? 0;
        final balance = opening + credit - debit;
        return {
          ...c,
          'balance': balance,
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _customers = enriched.cast<Map<String, dynamic>>();
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _customers = [];
        _filtered = [];
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    if (_query.isEmpty) {
      _filtered = _customers;
      return;
    }
    final q = _query.toLowerCase();
    _filtered = _customers.where((c) {
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
      await _loadCustomers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_activeBusinessName),
        actions: [
          IconButton(
            icon: const Icon(Icons.store_mall_directory),
            onPressed: _openBusinesses,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCustomers,
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
      floatingActionButton: FloatingActionButton(
        onPressed: _activeBusinessServerId == null
            ? null
            : () async {
                await Navigator.push(
                  context,
                  AppRoutes.onGenerateRoute(
                    const RouteSettings(name: AppRoutes.addCustomer),
                  ),
                );
                _loadCustomers();
              },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search customer',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                setState(() {
                  _query = v.trim();
                  _applyFilter();
                });
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _activeBusinessServerId == null
                    ? const Center(
                        child: Text('Select a business to continue.'))
                    : _filtered.isEmpty
                        ? const Center(child: Text('No customers yet.'))
                        : ListView.separated(
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final c = _filtered[index];
                              final balance =
                                  (c['balance'] as num?)?.toDouble() ?? 0;
                              return ListTile(
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
                                        name: AppRoutes.customerLedger,
                                        arguments: c,
                                      ),
                                    ),
                                  ).then((_) => _loadCustomers());
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
