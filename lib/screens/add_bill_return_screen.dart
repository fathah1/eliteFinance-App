import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';

class AddBillReturnScreen extends StatefulWidget {
  const AddBillReturnScreen({
    super.key,
    required this.isPurchase,
    required this.returnNumber,
  });

  final bool isPurchase;
  final int returnNumber;

  @override
  State<AddBillReturnScreen> createState() => _AddBillReturnScreenState();
}

class _AddBillReturnScreenState extends State<AddBillReturnScreen> {
  DateTime _date = DateTime.now();
  late int _returnNumber = widget.returnNumber;
  bool _saving = false;

  List<Map<String, dynamic>> _invoices = [];
  Map<String, dynamic>? _selectedInvoice;
  double _manualAmount = 0;
  String _settlementMode = 'credit_party';

  int? _businessId;

  bool get _isPurchase => widget.isPurchase;
  String get _title => _isPurchase ? 'Add Purchase Return' : 'Add Sale Return';
  String get _numberLabel =>
      _isPurchase ? 'Purchase Return Number' : 'Sale Return Number';
  String get _selectButton =>
      _isPurchase ? 'SELECT PURCHASE' : 'SELECT INVOICE';

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

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    if (businessId == null) return;

    try {
      final rows = _isPurchase
          ? await Api.getPurchases(businessId: businessId)
          : await Api.getSales(businessId: businessId);
      if (!mounted) return;
      setState(() {
        _businessId = businessId;
        _invoices = rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {}
  }

  String _money(double v) => 'AED ${v.toStringAsFixed(0)}';

  String _dateText(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year.toString().substring(2)}';
  }

  double get _amount {
    if (_selectedInvoice != null) {
      return _toDouble(_selectedInvoice!['total_amount']);
    }
    return _manualAmount;
  }

  List<Map<String, dynamic>> _invoiceItems(Map<String, dynamic> invoice) {
    final raw = invoice['items'];
    if (raw is! List) return const [];
    return raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return {
        'item_id': m['item_id'],
        'name': m['name'],
        'qty': _toInt(m['qty'], fallback: 0),
        'price': _toDouble(m['price']),
      };
    }).toList();
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

  String _apiDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _editReturnNumber() async {
    final c = TextEditingController(text: '$_returnNumber');
    final n = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Return Number'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
        ),
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
    setState(() => _returnNumber = n);
  }

  Future<void> _selectInvoice() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                _isPurchase
                    ? 'Select the Purchase for this Purchase Return'
                    : 'Select the Sale for this Sale Return',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: _invoices.length,
                  itemBuilder: (_, i) {
                    final inv = _invoices[i];
                    final date =
                        DateTime.tryParse((inv['date'] ?? '').toString()) ?? DateTime.now();
                    final name = (inv['party_name'] ?? '').toString().trim().isEmpty
                        ? (_isPurchase ? 'Walk-in Purchase' : 'Walk-in Sale')
                        : (inv['party_name'] ?? '').toString();
                    final number = _isPurchase
                        ? _toInt(inv['purchase_number'])
                        : _toInt(inv['bill_number']);
                    final total = _toDouble(inv['total_amount']);
                    final balance = _toDouble(inv['balance_due']);
                    return ListTile(
                      onTap: () => Navigator.pop(context, inv),
                      title: Text(name),
                      subtitle: Text(
                        '${_isPurchase ? 'Purchase' : 'Sale'} #$number • ${_dateText(date)}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_money(total),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            balance > 0 ? '${_money(balance)} Pending' : 'Fully Paid',
                            style: TextStyle(
                              color: balance > 0
                                  ? const Color(0xFFC6284D)
                                  : const Color(0xFF12965B),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null) return;
    setState(() {
      _selectedInvoice = selected;
      _manualAmount = 0;
    });
  }

  Future<void> _setManualAmount() async {
    final c = TextEditingController(
      text: _manualAmount > 0 ? _manualAmount.toStringAsFixed(0) : '',
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Manually'),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'Amount'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = double.tryParse(c.text.trim());
              if (v == null || v <= 0) return;
              Navigator.pop(context, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (amount == null) return;
    setState(() {
      _manualAmount = amount;
      _selectedInvoice = null;
    });
  }

  Future<void> _save() async {
    if (_businessId == null) return;
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter or select return amount')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isPurchase) {
        await Api.createPurchaseReturn(
          businessId: _businessId!,
          returnNumber: _returnNumber,
          date: _apiDate(_date),
          purchaseId: _selectedInvoice == null ? null : _toInt(_selectedInvoice!['id']),
          supplierId: _selectedInvoice == null
              ? null
              : _toInt(_selectedInvoice!['supplier_id']),
          settlementMode: _settlementMode,
          manualAmount: _selectedInvoice == null ? _manualAmount : null,
          items: _selectedInvoice == null ? null : _invoiceItems(_selectedInvoice!),
        );
      } else {
        await Api.createSaleReturn(
          businessId: _businessId!,
          returnNumber: _returnNumber,
          date: _apiDate(_date),
          saleId: _selectedInvoice == null ? null : _toInt(_selectedInvoice!['id']),
          customerId:
              _selectedInvoice == null ? null : _toInt(_selectedInvoice!['customer_id']),
          settlementMode: _settlementMode,
          manualAmount: _selectedInvoice == null ? _manualAmount : null,
          items: _selectedInvoice == null ? null : _invoiceItems(_selectedInvoice!),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Text(_title),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_numberLabel, style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('$_returnNumber',
                              style: const TextStyle(
                                  fontSize: 34 / 2, fontWeight: FontWeight.w700)),
                          IconButton(
                            onPressed: _editReturnNumber,
                            icon: const Icon(Icons.edit_outlined, color: brandBlue),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Date', style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month),
                      label: Text(_dateText(_date)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPurchase ? 'Add Purchase Details' : 'Add Invoice Details',
                  style: const TextStyle(fontSize: 34 / 2, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: _selectInvoice,
                      child: Text(_selectButton),
                    ),
                    TextButton(
                      onPressed: _setManualAmount,
                      child: const Text('ADD MANUALLY'),
                    ),
                  ],
                ),
                if (_selectedInvoice != null)
                  Text(
                    '${_isPurchase ? 'Purchase' : 'Sale'} #${_isPurchase ? _toInt(_selectedInvoice!['purchase_number']) : _toInt(_selectedInvoice!['bill_number'])} selected',
                    style: const TextStyle(color: Color(0xFF0B4F9E)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Settlement'),
                RadioListTile<String>(
                  value: 'credit_party',
                  groupValue: _settlementMode,
                  title: const Text('Credit to Party'),
                  onChanged: (v) => setState(() => _settlementMode = v!),
                ),
                RadioListTile<String>(
                  value: 'cash',
                  groupValue: _settlementMode,
                  title: const Text('Cash'),
                  onChanged: (v) => setState(() => _settlementMode = v!),
                ),
                RadioListTile<String>(
                  value: 'card',
                  groupValue: _settlementMode,
                  title: const Text('Card'),
                  onChanged: (v) => setState(() => _settlementMode = v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Text(
              'Total Amount  ${_money(_amount)}',
              style: const TextStyle(fontSize: 36 / 2, fontWeight: FontWeight.w700),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(_saving ? 'SAVING...' : 'SAVE RETURN'),
              ),
            ),
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
