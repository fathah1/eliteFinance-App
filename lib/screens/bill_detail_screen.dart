import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import 'add_bill_payment_screen.dart';
import 'add_bill_return_screen.dart';
import 'sale_invoice_screen.dart';

class BillDetailScreen extends StatefulWidget {
  const BillDetailScreen({
    super.key,
    required this.billId,
    required this.billNumber,
    required this.isPurchase,
  });

  final int billId;
  final int billNumber;
  final bool isPurchase;

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _bill;
  List<Map<String, dynamic>> _items = [];
  List<int> _linkedPayments = [];
  String _partyName = '';
  int? _partyId;
  String _statusLabel = '';
  Color _statusColor = const Color(0xFF12965B);
  int _nextPaymentNumber = 1;

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  DateTime _toDate(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse((value ?? '').toString()) ?? DateTime.now();
  }

  Map<String, dynamic> _paymentStatus({
    required double total,
    required double paid,
    required double balance,
  }) {
    if (total <= 0) {
      return {
        'label': 'Fully Paid',
        'color': const Color(0xFF12965B),
      };
    }
    if (balance > 0) {
      if (paid > 0) {
        return {
          'label': 'Partially Paid',
          'color': const Color(0xFFE67E22),
        };
      }
      return {
        'label': 'Unpaid',
        'color': const Color(0xFFC6284D),
      };
    }
    return {
      'label': 'Fully Paid',
      'color': const Color(0xFF12965B),
    };
  }

  int _parseBillNoFromNote(String note, String prefix) {
    if (!note.startsWith(prefix)) return 0;
    final m = RegExp('#(\\d+)').firstMatch(note);
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    if (businessId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      if (widget.isPurchase) {
        final purchases = await Api.getPurchases(businessId: businessId);
        _bill = purchases
            .map((e) => Map<String, dynamic>.from(e as Map))
            .firstWhere((e) => (e['id'] ?? 0) == widget.billId,
                orElse: () => {});
        final txs =
            await Api.getAllSupplierTransactions(businessId: businessId);
        final numbers = <int>[];
        var maxPaymentNo = 0;
        for (final raw in txs) {
          final t = Map<String, dynamic>.from(raw as Map);
          final ids = (t['purchase_ids'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              const <int>[];
          final singleId = (t['purchase_id'] is num)
              ? (t['purchase_id'] as num).toInt()
              : 0;
          final linked = ids.contains(widget.billId) || singleId == widget.billId;
          if (!linked) continue;
          final numRaw = t['payment_number'] ??
              _parseBillNoFromNote(
                (t['note'] ?? '').toString(),
                'Payment Out #',
              );
          final n = (numRaw is num) ? numRaw.toInt() : int.tryParse('$numRaw') ?? 0;
          if (n > 0) numbers.add(n);
          if (n > maxPaymentNo) maxPaymentNo = n;
        }
        _linkedPayments = numbers.toList();
        _nextPaymentNumber = maxPaymentNo + 1;
      } else {
        final sales = await Api.getSales(businessId: businessId);
        _bill = sales
            .map((e) => Map<String, dynamic>.from(e as Map))
            .firstWhere((e) => (e['id'] ?? 0) == widget.billId,
                orElse: () => {});
        final txs = await Api.getAllTransactions(businessId: businessId);
        final numbers = <int>[];
        var maxPaymentNo = 0;
        for (final raw in txs) {
          final t = Map<String, dynamic>.from(raw as Map);
          final ids = (t['sale_ids'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              const <int>[];
          final singleId = (t['sale_id'] is num)
              ? (t['sale_id'] as num).toInt()
              : 0;
          final linked = ids.contains(widget.billId) || singleId == widget.billId;
          if (!linked) continue;
          final numRaw = t['payment_number'] ??
              _parseBillNoFromNote(
                (t['note'] ?? '').toString(),
                'Payment In #',
              );
          final n = (numRaw is num) ? numRaw.toInt() : int.tryParse('$numRaw') ?? 0;
          if (n > 0) numbers.add(n);
          if (n > maxPaymentNo) maxPaymentNo = n;
        }
        _linkedPayments = numbers.toList();
        _nextPaymentNumber = maxPaymentNo + 1;
      }

      final bill = _bill ?? {};
      final party =
          (bill['party_name'] ?? bill['supplier_name'] ?? bill['customer_name'])
              .toString();
      _partyName = party.trim().isEmpty
          ? (widget.isPurchase ? 'Supplier' : 'Customer')
          : party;
      _partyId = widget.isPurchase
          ? (bill['supplier_id'] is num ? (bill['supplier_id'] as num).toInt() : null)
          : (bill['customer_id'] is num ? (bill['customer_id'] as num).toInt() : null);

      final itemsRaw = bill['items'];
      if (itemsRaw is List) {
        _items =
            itemsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _items = [];
      }

      final total = _toDouble(
        bill['total_amount'] ??
            bill['manual_amount'] ??
            bill['amount'],
      );
      final paid = _toDouble(
        bill['received_amount'] ??
            bill['paid_amount'],
      );
      final balance = _toDouble(bill['balance_due']);
      final status = _paymentStatus(
        total: total,
        paid: paid,
        balance: balance,
      );
      _statusLabel = status['label'] as String;
      _statusColor = status['color'] as Color;

      if (_linkedPayments.isEmpty && paid > 0) {
        _linkedPayments = [widget.billNumber];
      }
      _linkedPayments = _linkedPayments.toSet().toList()..sort();
    } catch (_) {}

    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    final bill = _bill ?? {};
    final total = _toDouble(
      bill['total_amount'] ?? bill['manual_amount'] ?? bill['amount'],
    );
    final tax = _toDouble(bill['vat_amount'] ?? bill['tax_amount']);
    final net = total;
    final gross = total;
    final createdAt = _toDate(bill['date'] ?? bill['created_at']);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Text(
          widget.isPurchase
              ? 'Purchase #${widget.billNumber}'
              : 'Sale Bill #${widget.billNumber}',
        ),
        actions: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Edit not implemented yet')),
              );
            },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Delete not implemented yet')),
              );
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _partyName,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Created On: ${DateFormat('dd MMM yy').format(createdAt)}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'AED ${total.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 18),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _statusLabel,
                            style: TextStyle(
                              color: _statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Continue with:',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final nextReturnNo = 1;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddBillReturnScreen(
                                isPurchase: widget.isPurchase,
                                returnNumber: nextReturnNo,
                              ),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF0B4F9E)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        child: Text(
                          widget.isPurchase
                              ? '+ PURCHASE RETURN'
                              : '+ SALE RETURN',
                          style: const TextStyle(
                            color: Color(0xFF0B4F9E),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (_statusLabel != 'Fully Paid') ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: (_partyId == null)
                              ? null
                              : () async {
                                  final balance = _toDouble(bill['balance_due']);
                                  final ok = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AddBillPaymentScreen(
                                        isPurchase: widget.isPurchase,
                                        paymentNumber: _nextPaymentNumber,
                                        initialPartyId: _partyId,
                                        initialDocIds: [widget.billId],
                                        initialAmount: balance > 0 ? balance : null,
                                      ),
                                    ),
                                  );
                                  if (ok == true) {
                                    if (mounted) {
                                      _load();
                                      Navigator.pop(context, true);
                                    }
                                  }
                                },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF0B4F9E)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          child: Text(
                            widget.isPurchase ? '+ PAYMENT OUT' : '+ PAYMENT IN',
                            style: const TextStyle(
                              color: Color(0xFF0B4F9E),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_linkedPayments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Linked transactions;',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    children: _linkedPayments
                        .map(
                          (n) => Text(
                            '${widget.isPurchase ? 'PAYMENT OUT' : 'PAYMENT IN'} #$n',
                            style: const TextStyle(
                              color: Color(0xFF0B4F9E),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                ..._items.map((item) {
                  final name = (item['name'] ?? '').toString();
                  final qty = _toDouble(item['quantity'] ?? item['qty'] ?? 1);
                  final price =
                      _toDouble(item['price'] ?? item['unit_price']);
                  final lineTotal =
                      _toDouble(item['total'] ?? (qty * price));
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE6EAF0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name),
                              const SizedBox(height: 4),
                              Text(
                                '${qty.toStringAsFixed(1)} x AED ${price.toStringAsFixed(0)}',
                                style:
                                    const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        Text('AED ${lineTotal.toStringAsFixed(0)}'),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 14),
                _amountRow('Net Amount', net),
                _amountRow('Taxes', tax),
                const SizedBox(height: 6),
                _amountRow(
                  'Gross Amount',
                  gross,
                  bold: true,
                  fontSize: 18,
                ),
                const SizedBox(height: 30),
                OutlinedButton(
                  onPressed: () {
                    if (widget.isPurchase) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Purchase PDF not available yet')),
                      );
                      return;
                    }
                    if (_bill == null || _bill!.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SaleInvoiceScreen(sale: _bill!),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF0B4F9E)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'VIEW PDF',
                    style: TextStyle(
                      color: Color(0xFF0B4F9E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _amountRow(String label, double amount,
      {bool bold = false, double fontSize = 14}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          'AED ${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
