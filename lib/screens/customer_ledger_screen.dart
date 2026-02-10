import 'package:flutter/material.dart';
import '../api.dart';
import '../routes.dart';

class CustomerLedgerScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerLedgerScreen({super.key, required this.customer});

  @override
  State<CustomerLedgerScreen> createState() => _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends State<CustomerLedgerScreen> {
  List<Map<String, dynamic>> _transactions = [];
  double _balance = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final tx = await Api.getCustomerTransactions(
        customerId: widget.customer['id'] as int,
      );
      final credit = tx
          .where((t) => t['type'] == 'CREDIT')
          .fold<double>(0, (sum, t) => sum + (t['amount'] as num).toDouble());
      final debit = tx
          .where((t) => t['type'] == 'DEBIT')
          .fold<double>(0, (sum, t) => sum + (t['amount'] as num).toDouble());
      final opening =
          (widget.customer['opening_balance'] as num?)?.toDouble() ?? 0;
      final balance = opening + credit - debit;

      if (!mounted) return;
      setState(() {
        _transactions = tx.cast<Map<String, dynamic>>();
        _balance = balance;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _transactions = [];
        _loading = false;
      });
    }
  }

  Color _balanceColor(double balance) {
    if (balance > 0) return Colors.red;
    if (balance < 0) return Colors.green;
    return Colors.grey;
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _deleteTx(int id) async {
    await Api.deleteTransaction(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.customer['name'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.sms),
            onPressed: () {
              final amount = _balance.abs().toStringAsFixed(2);
              final message =
                  'Hi, you have \u20b9$amount pending with ${name.toString()}';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Reminder: $message')),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            AppRoutes.onGenerateRoute(
              RouteSettings(
                name: AppRoutes.addEntry,
                arguments: {'customerId': widget.customer['id']},
              ),
            ),
          );
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey.shade200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Balance',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        _balance.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _balanceColor(_balance),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _transactions.isEmpty
                      ? const Center(child: Text('No entries yet.'))
                      : ListView.separated(
                          itemCount: _transactions.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final t = _transactions[index];
                            final amount = (t['amount'] as num)
                                .toDouble()
                                .toStringAsFixed(2);
                            final type = t['type'] as String;
                            final color =
                                type == 'CREDIT' ? Colors.red : Colors.green;
                            return ListTile(
                              title: Text((t['note'] ?? '').toString()),
                              subtitle:
                                  Text(_formatDate(t['created_at'] as String)),
                              trailing: Text(
                                '${type == 'CREDIT' ? '+' : '-'}$amount',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  AppRoutes.onGenerateRoute(
                                    RouteSettings(
                                      name: AppRoutes.addEntry,
                                      arguments: {
                                        'customerId': widget.customer['id'],
                                        'transaction': t,
                                      },
                                    ),
                                  ),
                                );
                                _load();
                              },
                              onLongPress: () => _deleteTx(t['id'] as int),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
