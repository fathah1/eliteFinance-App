import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  bool _loading = true;
  double _credit = 0;
  double _debit = 0;
  double _net = 0;
  int? _businessId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _businessId = prefs.getInt('active_business_server_id');
    await _load();
  }

  Future<void> _load() async {
    if (_businessId == null) {
      setState(() {
        _loading = false;
        _credit = 0;
        _debit = 0;
        _net = 0;
      });
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final transactions =
          await Api.getAllTransactions(businessId: _businessId!);
      final fromMs = _from.millisecondsSinceEpoch;
      final toMs = _to.millisecondsSinceEpoch;
      double credit = 0;
      double debit = 0;
      for (final t in transactions) {
        final raw = (t['created_at'] ?? '').toString();
        final dt = DateTime.tryParse(raw);
        if (dt == null) continue;
        final ms = dt.millisecondsSinceEpoch;
        if (ms < fromMs || ms > toMs) continue;

        final amount = (t['amount'] as num?)?.toDouble() ?? 0;
        final type = (t['type'] ?? '').toString();
        if (type == 'CREDIT') {
          credit += amount;
        } else if (type == 'DEBIT') {
          debit += amount;
        }
      }

      if (!mounted) return;
      setState(() {
        _credit = credit;
        _debit = debit;
        _net = credit - debit;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('From: ${_from.toLocal().toString().split(' ').first}'),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _from,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _from = picked;
                      });
                      _load();
                    }
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text('To:   ${_to.toLocal().toString().split(' ').first}'),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _to,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _to = picked;
                      });
                      _load();
                    }
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _loading
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      ListTile(
                        title: const Text('Total Credit'),
                        trailing: Text(_credit.toStringAsFixed(2)),
                      ),
                      ListTile(
                        title: const Text('Total Debit'),
                        trailing: Text(_debit.toStringAsFixed(2)),
                      ),
                      ListTile(
                        title: const Text('Net Balance'),
                        trailing: Text(_net.toStringAsFixed(2)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Export coming soon.'),
                            ),
                          );
                        },
                        child: const Text('Export'),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
