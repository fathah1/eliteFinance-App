import 'package:flutter/material.dart';
import '../api.dart';
import '../routes.dart';
import 'entry_detail_screen.dart';

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

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d $m $y • $h:$min';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final tx = await Api.getCustomerTransactions(
        customerId: widget.customer['id'] as int,
      );

      final opening = 0.0;
      final list = tx
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      list.sort((a, b) {
        final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime(1970);
        final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime(1970);
        return da.compareTo(db);
      });

      double running = opening;
      for (final t in list) {
        final type = (t['type'] ?? '').toString();
        final amount = _asDouble(t['amount']);
        if (type == 'CREDIT') {
          running += amount;
        } else {
          running -= amount;
        }
        t['running_balance'] = running;
      }

      final credit = list
          .where((t) => t['type'] == 'CREDIT')
          .fold<double>(0, (sum, t) => sum + _asDouble(t['amount']));
      final debit = list
          .where((t) => t['type'] == 'DEBIT')
          .fold<double>(0, (sum, t) => sum + _asDouble(t['amount']));
      final balance = opening + credit - debit;

      if (!mounted) return;
      setState(() {
        _transactions = list.reversed.toList();
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

  Future<void> _openAdd(String type) async {
    await Navigator.push(
      context,
      AppRoutes.onGenerateRoute(
        RouteSettings(
          name: AppRoutes.addEntry,
          arguments: {
            'customerId': widget.customer['id'],
            'initialType': type,
          },
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    final name = (widget.customer['name'] ?? '').toString();
    final absBalance = _balance.abs().toStringAsFixed(0);
    final isSettled = _balance == 0;
    final isPositive = _balance > 0;
    final balanceLabel = isSettled
        ? 'Settled up'
        : isPositive
            ? 'You gave'
            : 'You got';
    final balanceColor =
        isSettled ? Colors.black : (isPositive ? Colors.red : Colors.green);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'A',
                style: const TextStyle(color: brandBlue),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 16)),
                const Text('Customer', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: brandBlue,
            padding: const EdgeInsets.all(12),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(balanceLabel),
                        Text(
                          isSettled ? '0' : 'AED $absBalance',
                          style: TextStyle(
                            color: balanceColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Set collection reminder'),
                    trailing: TextButton(
                      onPressed: () {},
                      child: const Text('SET DATE'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                _QuickAction(icon: Icons.picture_as_pdf, label: 'Report'),
                // _QuickAction(icon: Icons.whatsapp, label: 'Reminder'),
                _QuickAction(icon: Icons.sms, label: 'SMS'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _transactions.isEmpty
                    ? const Center(child: Text('No entries yet.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _transactions.length,
                        itemBuilder: (context, index) {
                          final t = _transactions[index];
                          final amount = _asDouble(t['amount']);
                          final type = (t['type'] ?? '').toString();
                          final running = _asDouble(t['running_balance']);
                              return InkWell(
                                onTap: () {
                              final attachment = (t['attachment_path'] ?? '').toString();
                              final attachmentUrl = attachment.isNotEmpty
                                  ? 'https://eliteposs.com/financeserver/public/storage/$attachment'
                                  : '';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EntryDetailScreen(
                                    title: name,
                                    entry: t,
                                    runningBalance: running,
                                    attachmentUrl: attachmentUrl,
                                    onEdit: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        AppRoutes.onGenerateRoute(
                                          RouteSettings(
                                            name: AppRoutes.addEntry,
                                            arguments: {
                                              'customerId':
                                                  widget.customer['id'],
                                              'transaction': t,
                                            },
                                          ),
                                        ),
                                      ).then((_) => _load());
                                    },
                                    onDelete: () async {
                                      await Api.deleteTransaction(
                                          t['id'] as int);
                                      if (!context.mounted) return;
                                      Navigator.pop(context);
                                      _load();
                                    },
                                  ),
                                ),
                              );
                            },
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(_formatDate(
                                              t['created_at'] as String)),
                                          const SizedBox(height: 6),
                                          Text(
                                              'Bal. AED ${running.toStringAsFixed(0)}'),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 90,
                                    color: type == 'CREDIT'
                                        ? const Color(0xFFFDEDED)
                                        : Colors.transparent,
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      type == 'CREDIT'
                                          ? 'AED ${amount.toStringAsFixed(0)}'
                                          : '',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 90,
                                    color: type == 'DEBIT'
                                        ? const Color(0xFFE9F7EF)
                                        : Colors.transparent,
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      type == 'DEBIT'
                                          ? 'AED ${amount.toStringAsFixed(0)}'
                                          : '',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if ((t['attachment_path'] ?? '').toString().isNotEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Icon(Icons.attachment, size: 16),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _openAdd('CREDIT'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('YOU GAVE AED'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _openAdd('DEBIT'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('YOU GOT AED'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;

  const _QuickAction({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF0B4F9E)),
        const SizedBox(height: 4),
        Text(label),
      ],
    );
  }
}
