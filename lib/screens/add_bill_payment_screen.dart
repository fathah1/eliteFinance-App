import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';

class AddBillPaymentScreen extends StatefulWidget {
  const AddBillPaymentScreen({
    super.key,
    required this.isPurchase,
    required this.paymentNumber,
  });

  final bool isPurchase;
  final int paymentNumber;

  @override
  State<AddBillPaymentScreen> createState() => _AddBillPaymentScreenState();
}

class _AddBillPaymentScreenState extends State<AddBillPaymentScreen> {
  bool get _isPurchase => widget.isPurchase;

  late int _paymentNumber = widget.paymentNumber;
  DateTime _date = DateTime.now();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String _paymentMode = 'cash';
  bool _saving = false;

  int? _businessId;
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _parties = [];
  int? _selectedPartyId;
  final Set<int> _selectedDocIds = {};

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _apiDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _dateText(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year.toString().substring(2)}';
  }

  String _money(double v) => 'AED ${v.toStringAsFixed(0)}';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    if (businessId == null) return;

    try {
      final docs = _isPurchase
          ? await Api.getPurchases(businessId: businessId)
          : await Api.getSales(businessId: businessId);
      final rows = docs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final pendingRows = rows.where((d) => _toDouble(d['balance_due']) > 0).toList();

      final partiesMap = <int, Map<String, dynamic>>{};
      for (final d in pendingRows) {
        final id = _isPurchase ? _toInt(d['supplier_id']) : _toInt(d['customer_id']);
        if (id <= 0) continue;
        partiesMap[id] = {
          'id': id,
          'name': (d['party_name'] ?? '').toString().trim().isEmpty
              ? (_isPurchase ? 'Supplier' : 'Customer')
              : (d['party_name'] ?? '').toString(),
        };
      }

      if (!mounted) return;
      setState(() {
        _businessId = businessId;
        _docs = pendingRows;
        _parties = partiesMap.values.toList();
        _selectedPartyId = _parties.isEmpty ? null : _toInt(_parties.first['id']);
        _selectedDocIds
          ..clear()
          ..addAll(_pendingDocs.map((e) => _docId(e)));
        _amountController.text = _pendingTotal.toStringAsFixed(0);
      });
    } catch (_) {}
  }

  int _docId(Map<String, dynamic> d) => _toInt(d['id']);

  int _docNumber(Map<String, dynamic> d) =>
      _isPurchase ? _toInt(d['purchase_number']) : _toInt(d['bill_number']);

  int _docPartyId(Map<String, dynamic> d) =>
      _isPurchase ? _toInt(d['supplier_id']) : _toInt(d['customer_id']);

  List<Map<String, dynamic>> get _pendingDocs {
    if (_selectedPartyId == null) return const [];
    return _docs.where((d) => _docPartyId(d) == _selectedPartyId).toList();
  }

  double get _pendingTotal =>
      _pendingDocs.fold(0, (sum, d) => sum + _toDouble(d['balance_due']));

  double get _selectedPendingTotal {
    double sum = 0;
    for (final d in _pendingDocs) {
      if (_selectedDocIds.contains(_docId(d))) {
        sum += _toDouble(d['balance_due']);
      }
    }
    return sum;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _editPaymentNumber() async {
    final c = TextEditingController(text: '$_paymentNumber');
    final n = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Payment Number'),
        content: TextField(controller: c, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = int.tryParse(c.text.trim());
              if (v == null || v <= 0) return;
              Navigator.pop(context, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (n == null) return;
    setState(() => _paymentNumber = n);
  }

  Future<void> _save() async {
    if (_businessId == null || _selectedPartyId == null) return;
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter payment amount')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isPurchase) {
        await Api.createPurchasePayment(
          businessId: _businessId!,
          paymentNumber: _paymentNumber,
          date: _apiDate(_date),
          supplierId: _selectedPartyId!,
          amount: amount,
          paymentMode: _paymentMode,
          note: _noteController.text.trim(),
          purchaseIds: _selectedDocIds.toList(),
        );
      } else {
        await Api.createSalePayment(
          businessId: _businessId!,
          paymentNumber: _paymentNumber,
          date: _apiDate(_date),
          customerId: _selectedPartyId!,
          amount: amount,
          paymentMode: _paymentMode,
          note: _noteController.text.trim(),
          saleIds: _selectedDocIds.toList(),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const maroon = Color(0xFF9B154D);
    final heading = _isPurchase ? 'You Paid' : 'You Got';
    final selectedParty = _parties.firstWhere(
      (p) => _toInt(p['id']) == _selectedPartyId,
      orElse: () => {'name': _isPurchase ? 'Supplier' : 'Customer'},
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: maroon,
        title: Text('$heading ${_amountController.text.isEmpty ? 'AED 0' : 'AED ${_amountController.text.trim()}'} to ${selectedParty['name']}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text('Payment Number  $_paymentNumber'),
                      IconButton(
                        onPressed: _editPaymentNumber,
                        icon: const Icon(Icons.edit, size: 18),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text('Date  ${_apiDate(_date)}'),
                    IconButton(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.edit, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: DropdownButton<int>(
              value: _selectedPartyId,
              isExpanded: true,
              underline: const SizedBox(),
              hint: Text(_isPurchase ? 'Select Supplier' : 'Select Customer'),
              items: _parties
                  .map(
                    (p) => DropdownMenuItem<int>(
                      value: _toInt(p['id']),
                      child: Text((p['name'] ?? '').toString()),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _selectedPartyId = v;
                  _selectedDocIds
                    ..clear()
                    ..addAll(_pendingDocs.map((e) => _docId(e)));
                  _amountController.text = _pendingTotal.toStringAsFixed(0);
                });
              },
            ),
          ),
          const SizedBox(height: 10),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: 'AED ',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'cash',
                  groupValue: _paymentMode,
                  title: const Text('Cash'),
                  onChanged: (v) => setState(() => _paymentMode = v!),
                ),
                RadioListTile<String>(
                  value: 'card',
                  groupValue: _paymentMode,
                  title: const Text('Card'),
                  onChanged: (v) => setState(() => _paymentMode = v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                hintText: 'Enter details (items, bill no., quantity, etc.)',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPurchase ? 'Pending Purchases' : 'Pending Sales',
                  style: const TextStyle(fontSize: 34 / 2, fontWeight: FontWeight.w600),
                ),
                Text(
                  _isPurchase
                      ? 'Select purchases for this Payment'
                      : 'Select sales for this Payment',
                ),
                const SizedBox(height: 8),
                if (_pendingDocs.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F7EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'All Settled!',
                      style: TextStyle(color: Color(0xFF12965B)),
                    ),
                  )
                else
                  ..._pendingDocs.map((d) {
                    final id = _docId(d);
                    final selected = _selectedDocIds.contains(id);
                    final date =
                        DateTime.tryParse((d['date'] ?? '').toString()) ?? DateTime.now();
                    final pending = _toDouble(d['balance_due']);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedDocIds.add(id);
                          } else {
                            _selectedDocIds.remove(id);
                          }
                        });
                      },
                      title: Text('#${_docNumber(d)}'),
                      subtitle: Text(_dateText(date)),
                      secondary: Text(
                        '${_money(pending)} Pending',
                        style: const TextStyle(color: Color(0xFFC6284D)),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                Text(
                  'Selected pending: ${_money(_selectedPendingTotal)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: maroon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_saving ? 'SAVING...' : 'SAVE'),
          ),
        ],
      ),
    );
  }
}

String _month(int m) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return months[m - 1];
}
