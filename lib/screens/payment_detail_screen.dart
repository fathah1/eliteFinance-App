import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import 'add_bill_payment_screen.dart';

class PaymentDetailScreen extends StatefulWidget {
  const PaymentDetailScreen({
    super.key,
    required this.paymentId,
    required this.paymentNumber,
    required this.isPurchase,
    required this.partyName,
    required this.amount,
    required this.paymentMode,
    required this.date,
  });

  final int paymentId;
  final int paymentNumber;
  final bool isPurchase;
  final String partyName;
  final double amount;
  final String paymentMode;
  final DateTime date;

  @override
  State<PaymentDetailScreen> createState() => _PaymentDetailScreenState();
}

class _PaymentDetailScreenState extends State<PaymentDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _payment;
  List<Map<String, dynamic>> _allocations = [];

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  DateTime _toDate(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse((value ?? '').toString()) ?? widget.date;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    if (businessId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final rows = widget.isPurchase
          ? await Api.getAllSupplierTransactions(businessId: businessId)
          : await Api.getAllTransactions(businessId: businessId);
      final match = rows
          .map((e) => Map<String, dynamic>.from(e as Map))
          .firstWhere((e) => (e['id'] ?? 0) == widget.paymentId, orElse: () => {});
      if (match.isNotEmpty) {
        _payment = match;
        final alloc = match['allocations'];
        if (alloc is List) {
          _allocations = alloc
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _share() async {
    final title = widget.isPurchase
        ? 'Payment Out #${widget.paymentNumber}'
        : 'Payment In #${widget.paymentNumber}';
    await Share.share('$title\nAED ${widget.amount.toStringAsFixed(0)}');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Payment'),
        content: const Text('Are you sure you want to delete this payment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (widget.isPurchase) {
        await Api.deleteSupplierTransaction(widget.paymentId);
      } else {
        await Api.deleteTransaction(widget.paymentId);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    final title = widget.isPurchase
        ? 'Payment Out #${widget.paymentNumber}'
        : 'Payment In #${widget.paymentNumber}';
    final mode = widget.paymentMode.toUpperCase();
    final date = _toDate(_payment?['created_at'] ?? widget.date);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Text(title),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFFEAF2FF),
                            child: Text(
                              widget.partyName.isNotEmpty
                                  ? widget.partyName[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.partyName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('hh:mm a dd MMM yyyy').format(date),
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'AED ${widget.amount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(mode, style: const TextStyle(color: Colors.black54)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(),
                      const Text(
                        'Adjusted Invoices',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      if (_allocations.isEmpty)
                        const Text('-', style: TextStyle(color: Colors.black45))
                      else
                        ..._allocations.map((a) {
                          final billNo = (a['bill_number'] ??
                                  a['purchase_number'] ??
                                  a['sale_id'] ??
                                  a['purchase_id'] ??
                                  '')
                              .toString();
                          final amt = _toDouble(a['applied_amount']);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('#$billNo'),
                                ),
                                Text('AED ${amt.toStringAsFixed(0)}'),
                              ],
                            ),
                          );
                        }),
                      if (_payment != null) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            final allocs = _allocations
                                .map((a) => (a['sale_id'] ?? a['purchase_id']))
                                .whereType<num>()
                                .map((e) => e.toInt())
                                .toList();
                            Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddBillPaymentScreen(
                                  isPurchase: widget.isPurchase,
                                  paymentNumber: widget.paymentNumber,
                                  initialPartyId:
                                      _payment?['customer_id'] ?? _payment?['supplier_id'],
                                  initialDocIds: allocs,
                                  initialAmount: widget.amount,
                                  initialNote: (_payment?['note'] ?? '').toString(),
                                  initialPaymentMode: (_payment?['payment_mode'] ??
                                          widget.paymentMode)
                                      .toString()
                                      .toLowerCase()
                                      .contains('card')
                                      ? 'card'
                                      : 'cash',
                                  initialDate: date,
                                  isEdit: true,
                                  transactionId: widget.paymentId,
                                ),
                              ),
                            ).then((updated) {
                              if (updated == true) {
                                _load();
                                if (mounted) {
                                  Navigator.pop(context, true);
                                }
                              }
                            });
                          },
                          child: const Text('EDIT TRANSACTION'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: _payment != null
              ? Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('DELETE'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFC6284D),
                          side: const BorderSide(color: Color(0xFFC6284D)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share),
                        label: const Text('SHARE'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                )
              : ElevatedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share),
                  label: const Text('SHARE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
        ),
      ),
    );
  }
}
