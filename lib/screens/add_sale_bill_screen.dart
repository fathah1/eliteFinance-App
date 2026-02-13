import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import 'add_customer_screen.dart';
import 'add_item_screen.dart';
import 'sale_invoice_screen.dart';

class SaleBillDraft {
  SaleBillDraft({
    required this.saved,
    this.sale,
  });

  final bool saved;
  final Map<String, dynamic>? sale;
}

class _BillLineItem {
  _BillLineItem({
    required this.id,
    required this.name,
    required this.price,
    required this.currentStock,
    this.photoUrl,
    this.qty = 1,
  });

  final int id;
  final String name;
  final double price;
  final int currentStock;
  final String? photoUrl;
  int qty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'currentStock': currentStock,
      'photoUrl': photoUrl,
      'qty': qty,
    };
  }
}

class _AdditionalCharge {
  _AdditionalCharge({required this.label, required this.amount});
  final String label;
  final double amount;
}

class AddSaleBillScreen extends StatefulWidget {
  final int billNumber;
  const AddSaleBillScreen({super.key, required this.billNumber});

  @override
  State<AddSaleBillScreen> createState() => _AddSaleBillScreenState();
}

class _AddSaleBillScreenState extends State<AddSaleBillScreen> {
  final _amountController = TextEditingController();
  DateTime _date = DateTime.now();
  int _billNumber = 0;
  int? _partyId;
  String? _partyName;
  String? _partyPhone;
  String _paymentMode = 'unpaid';
  DateTime? _dueDate;
  List<_BillLineItem> _lineItems = [];
  final List<_AdditionalCharge> _additionalCharges = [];
  double _discount = 0;
  String _discountType = 'aed'; // aed | percent
  String? _discountLabel;
  bool _optionalExpanded = true;
  final _receivedController = TextEditingController();
  final _paymentRefController = TextEditingController();
  String _privateNote = '';
  final List<String> _notePhotos = [];

  double get _itemsSubtotal =>
      _lineItems.fold<double>(0, (sum, item) => sum + (item.price * item.qty));

  double get _additionalChargeTotal =>
      _additionalCharges.fold<double>(0, (sum, charge) => sum + charge.amount);

  double get _saleBillAmount {
    final base = _lineItems.isNotEmpty
        ? _itemsSubtotal
        : (double.tryParse(_amountController.text.trim()) ?? 0);
    final discountAmount = _discountAmount(base + _additionalChargeTotal);
    final total = base + _additionalChargeTotal - discountAmount;
    return total < 0 ? 0 : total;
  }

  double _discountAmount(double amountBeforeDiscount) {
    if (_discount <= 0) return 0;
    if (_discountType == 'percent') {
      final pct = _discount.clamp(0, 100);
      return amountBeforeDiscount * (pct / 100);
    }
    return _discount;
  }

  @override
  void initState() {
    super.initState();
    _billNumber = widget.billNumber;
    _receivedController.text = '0';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _receivedController.dispose();
    _paymentRefController.dispose();
    super.dispose();
  }

  double get _receivedAmount =>
      double.tryParse(_receivedController.text.trim()) ?? 0;

  double get _balanceDue {
    if (_paymentMode == 'unpaid') return _saleBillAmount;
    final due = _saleBillAmount - _receivedAmount;
    return due > 0 ? due : 0;
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

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _dueDate = picked);
  }

  String _toApiDate(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  Future<void> _openNotesAndPhotos() async {
    final noteController = TextEditingController(text: _privateNote);
    final tempPhotos = List<String>.from(_notePhotos);
    final picker = ImagePicker();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Add Notes and Photos',
                          style: TextStyle(
                              fontSize: 34 / 2, fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Add Notes for your personal reference'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Enter your notes here',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: List.generate(4, (index) {
                      final hasPhoto = index < tempPhotos.length;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () async {
                              if (hasPhoto) {
                                setSheet(() => tempPhotos.removeAt(index));
                                return;
                              }
                              final file = await picker.pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 80,
                              );
                              if (file == null) return;
                              setSheet(() => tempPhotos.add(file.path));
                            },
                            child: Container(
                              height: 82,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black26),
                              ),
                              child: hasPhoto
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(tempPhotos[index]),
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : const Icon(Icons.add_a_photo_outlined,
                                      color: Colors.black38),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('SAVE'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != true) return;
    setState(() {
      _privateNote = noteController.text.trim();
      _notePhotos
        ..clear()
        ..addAll(tempPhotos);
    });
  }

  Future<void> _editBillNumber() async {
    final controller = TextEditingController(text: '$_billNumber');
    final value = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Sale Bill Number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Enter bill number'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null || parsed <= 0) return;
              Navigator.pop(context, parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    setState(() => _billNumber = value);
  }

  Future<void> _openPartyPicker() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _BillPartyPickerSheet(),
    );

    if (selected == null) return;
    setState(() {
      _partyId = selected['id'] == null
          ? null
          : int.tryParse(selected['id'].toString());
      _partyName = selected['name'];
      _partyPhone = selected['phone'];
    });
  }

  Future<void> _openInventoryPicker() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    if (businessId == null || !mounted) return;

    final selected = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => _InventoryPickerSheet(
        businessId: businessId,
        preselectedItems: _lineItems.map((e) => e.toMap()).toList(),
      ),
    );

    if (selected == null) return;

    final mapped = selected
        .map((m) => _BillLineItem(
              id: m['id'] as int,
              name: (m['name'] ?? '').toString(),
              price: (m['price'] as num).toDouble(),
              currentStock: m['currentStock'] as int,
              photoUrl: m['photoUrl'] as String?,
              qty: m['qty'] as int? ?? 1,
            ))
        .toList();

    setState(() {
      _lineItems = mapped;
      _amountController.text = _itemsSubtotal.toStringAsFixed(0);
    });
  }

  void _changeLineQty(int index, int delta) {
    setState(() {
      final next = _lineItems[index].qty + delta;
      _lineItems[index].qty = next < 1 ? 1 : next;
      _amountController.text = _itemsSubtotal.toStringAsFixed(0);
    });
  }

  void _removeLineItem(int index) {
    setState(() {
      _lineItems.removeAt(index);
      _amountController.text = _itemsSubtotal.toStringAsFixed(0);
    });
  }

  Future<void> _openAdditionalCharge() async {
    final labelController = TextEditingController();
    final amountController = TextEditingController();
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Additional Charges'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(hintText: 'Label'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Amount'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount < 0) return;
              Navigator.pop(context, {
                'label': labelController.text.trim(),
                'amount': amount,
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (data == null) return;
    setState(() {
      _additionalCharges.add(
        _AdditionalCharge(
          label: ((data['label'] as String?)?.trim().isEmpty ?? true)
              ? 'Additional charge'
              : (data['label'] as String).trim(),
          amount: (data['amount'] as num).toDouble(),
        ),
      );
    });
  }

  Future<void> _openDiscount() async {
    final labelController = TextEditingController(
      text: _discountLabel ?? 'Discount',
    );
    final amountController = TextEditingController(
      text: _discount == 0 ? '' : _discount.toStringAsFixed(0),
    );
    String tempType = _discountType;

    final data = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Add Discount',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setSheet(() => tempType = 'aed'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: tempType == 'aed'
                                    ? const Color(0xFF0B4F9E)
                                    : Colors.black26,
                              ),
                              color: tempType == 'aed'
                                  ? const Color(0xFFEAF2FF)
                                  : Colors.white,
                            ),
                            child: const Center(
                              child: Text('Discount in AED'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => setSheet(() => tempType = 'percent'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: tempType == 'percent'
                                    ? const Color(0xFF0B4F9E)
                                    : Colors.black26,
                              ),
                              color: tempType == 'percent'
                                  ? const Color(0xFFEAF2FF)
                                  : Colors.white,
                            ),
                            child: const Center(
                              child: Text('Discount in %'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(hintText: 'Label'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: tempType == 'percent'
                          ? 'Discount percentage'
                          : 'Discount amount',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final amount =
                                double.tryParse(amountController.text.trim());
                            if (amount == null || amount < 0) return;
                            Navigator.pop(context, {
                              'label': labelController.text.trim(),
                              'amount': amount,
                              'type': tempType,
                            });
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (data == null) return;
    setState(() {
      _discountLabel = ((data['label'] as String?)?.trim().isEmpty ?? true)
          ? 'Discount'
          : (data['label'] as String).trim();
      _discount = (data['amount'] as num).toDouble();
      _discountType = (data['type'] as String?) ?? 'aed';
    });
  }

  Future<void> _openCreateItemFromBill() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    if (businessId == null || !mounted) return;

    final data = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddItemScreen(type: 'product'),
      ),
    );

    if (data == null) return;

    await Api.createItem(
      businessId: businessId,
      type: 'product',
      name: (data['name'] ?? '').toString(),
      unit: (data['unit'] ?? 'PCS').toString(),
      salePrice: (data['salePrice'] as num?)?.toDouble() ?? 0,
      purchasePrice: (data['purchasePrice'] as num?)?.toDouble() ?? 0,
      taxIncluded: (data['taxIncluded'] as bool?) ?? true,
      openingStock: (data['openingStock'] as int?) ?? 0,
      lowStockAlert: (data['lowStockAlert'] as int?) ?? 0,
      photoPath: data['photoPath'] as String?,
    );

    if (!mounted) return;
    await _openInventoryPicker();
  }

  Future<void> _save() async {
    if (_saleBillAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter amount or add items')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    if (businessId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active business selected')),
      );
      return;
    }

    try {
      final sale = await Api.createSale(
        businessId: businessId,
        billNumber: _billNumber,
        date: _toApiDate(_date),
        partyName: _partyName,
        partyPhone: _partyPhone,
        customerId: _partyId,
        paymentMode: _paymentMode,
        dueDate: _dueDate == null ? null : _toApiDate(_dueDate!),
        receivedAmount: (_paymentMode == 'cash' || _paymentMode == 'card')
            ? _receivedAmount
            : null,
        paymentReference: _paymentRefController.text.trim(),
        privateNotes: _privateNote,
        photoPaths: _notePhotos,
        manualAmount: double.tryParse(_amountController.text.trim()) ?? 0,
        lineItems: _lineItems
            .map((e) => {
                  'item_id': e.id,
                  'name': e.name,
                  'price': e.price,
                  'qty': e.qty,
                })
            .toList(),
        additionalCharges: _additionalCharges
            .map((e) => {
                  'label': e.label,
                  'amount': e.amount,
                })
            .toList(),
        discountValue: _discount,
        discountType: _discountType,
        discountLabel: _discountLabel,
      );
      if (!mounted) return;
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => SaleInvoiceScreen(sale: sale),
        ),
      );
      if (!mounted) return;
      if (result == 'create_new') {
        setState(() {
          _billNumber += 1;
          _partyId = null;
          _partyName = null;
          _partyPhone = null;
          _paymentMode = 'unpaid';
          _dueDate = null;
          _lineItems = [];
          _additionalCharges.clear();
          _discount = 0;
          _discountType = 'aed';
          _discountLabel = null;
          _amountController.clear();
          _receivedController.text = '0';
          _paymentRefController.clear();
          _privateNote = '';
          _notePhotos.clear();
        });
        return;
      }
      Navigator.pop(context, SaleBillDraft(saved: true, sale: sale));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    final dateText =
        '${_date.day.toString().padLeft(2, '0')} ${_month(_date.month)} ${_date.year.toString().substring(2)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: const Text('Sale Bill'),
      ),
      body: ListView(
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
                      const Text('Sale Bill Number',
                          style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '$_billNumber',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _editBillNumber,
                            child: const Icon(Icons.edit,
                                color: brandBlue, size: 18),
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
                      label: Text(dateText),
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
                const Text('Bill To', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 12),
                if (_partyName == null)
                  InkWell(
                    onTap: _openPartyPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.search, color: Colors.black45),
                          SizedBox(width: 10),
                          Text('Search from your parties',
                              style: TextStyle(color: Colors.black45)),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, color: Colors.black54),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_partyName${_partyPhone == null ? '' : ' · $_partyPhone'}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(_partyPhone ?? '',
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 14)),
                              const SizedBox(height: 6),
                              const Text('EDIT PARTY DETAILS',
                                  style: TextStyle(
                                      color: brandBlue,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _partyId = null;
                              _partyName = null;
                              _partyPhone = null;
                            });
                          },
                          icon: const Icon(Icons.cancel,
                              color: Colors.black26, size: 26),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _openPartyPicker,
                  child: const Text('+ ADD NEW PARTY',
                      style: TextStyle(
                          color: brandBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
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
                if (_lineItems.isEmpty) ...[
                  const Text('Items', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _openInventoryPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              color: Colors.black45),
                          SizedBox(width: 10),
                          Text('Enter items from inventory',
                              style: TextStyle(color: Colors.black45)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _openCreateItemFromBill,
                    child: const Text('+ ADD NEW ITEM',
                        style: TextStyle(
                            color: brandBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Sale Bill Amount',
                            style: TextStyle(
                                fontSize: 34 / 2, fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.right,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Enter Amount',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text('${_lineItems.length} Item',
                      style:
                          const TextStyle(fontSize: 16, color: Colors.black54)),
                  const SizedBox(height: 8),
                  ..._lineItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Text(
                                  '${item.qty} x AED ${item.price.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontSize: 16, color: Colors.black54),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () => _changeLineQty(
                                          _lineItems.indexOf(item), -1),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border:
                                              Border.all(color: Colors.black26),
                                        ),
                                        child:
                                            const Icon(Icons.remove, size: 16),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('${item.qty}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => _changeLineQty(
                                          _lineItems.indexOf(item), 1),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border:
                                              Border.all(color: Colors.black26),
                                        ),
                                        child: const Icon(Icons.add, size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'AED ${(item.qty * item.price).toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () =>
                                    _removeLineItem(_lineItems.indexOf(item)),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.delete_outline,
                                        size: 16, color: Colors.red),
                                    SizedBox(width: 4),
                                    Text(
                                      'Remove',
                                      style: TextStyle(
                                          color: Colors.red, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _openInventoryPicker,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF3FB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.inventory_2_outlined, color: brandBlue),
                          SizedBox(width: 10),
                          Text('EDIT OR ADD ITEMS',
                              style: TextStyle(
                                  color: brandBlue,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18 / 1.4)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Item Sub-Total',
                          style: TextStyle(
                              fontSize: 34 / 2, fontWeight: FontWeight.w500)),
                      Text('AED ${_itemsSubtotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 34 / 2, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _openAdditionalCharge,
                    child: const Row(
                      children: [
                        Icon(Icons.local_offer_outlined, color: Colors.black54),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text('Additional Charges',
                              style: TextStyle(fontSize: 32 / 2)),
                        ),
                        Icon(Icons.chevron_right, color: Colors.black26),
                      ],
                    ),
                  ),
                  if (_additionalCharges.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ..._additionalCharges.asMap().entries.map((entry) {
                      final index = entry.key;
                      final charge = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                charge.label,
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                            Text('AED ${charge.amount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _additionalCharges.removeAt(index);
                                });
                              },
                              child: const Icon(Icons.close,
                                  size: 16, color: Colors.red),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _openDiscount,
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('+ ADD DISCOUNT',
                          style: TextStyle(
                              color: brandBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ),
                  ),
                  if (_discount > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_discountLabel ?? 'Discount',
                            style: const TextStyle(color: Colors.black54)),
                        Text(
                            _discountType == 'percent'
                                ? '- ${_discount.toStringAsFixed(0)}% (AED ${_discountAmount(_itemsSubtotal + _additionalChargeTotal).toStringAsFixed(0)})'
                                : '- AED ${_discount.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sale Bill Amount',
                          style: TextStyle(
                              fontSize: 34 / 2, fontWeight: FontWeight.w600)),
                      Text('AED ${_saleBillAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 34 / 2, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Optional Fields'),
                  subtitle: const Text('Printed on the Invoice'),
                  trailing: Icon(
                    _optionalExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                  onTap: () =>
                      setState(() => _optionalExpanded = !_optionalExpanded),
                ),
                if (_optionalExpanded) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Private to You',
                          style: TextStyle(color: Colors.black38)),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.note_alt_outlined),
                    title: const Text('Add Notes and Photos'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openNotesAndPhotos,
                  ),
                  if (_privateNote.isNotEmpty || _notePhotos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_privateNote.isNotEmpty ? "Notes saved" : ""}${_privateNote.isNotEmpty && _notePhotos.isNotEmpty ? " · " : ""}${_notePhotos.isNotEmpty ? "${_notePhotos.length} photo(s)" : ""}',
                          style: const TextStyle(color: Color(0xFF0B4F9E)),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _paymentOption('unpaid', 'Unpaid'),
                _paymentOption('cash', 'Cash'),
                _paymentOption('card', 'Card'),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                if (_paymentMode == 'unpaid')
                  ListTile(
                    title: const Text('+ DUE DATE',
                        style: TextStyle(
                            color: brandBlue, fontWeight: FontWeight.w700)),
                    subtitle: _dueDate == null
                        ? null
                        : Text(
                            '${_dueDate!.day.toString().padLeft(2, '0')} ${_month(_dueDate!.month)} ${_dueDate!.year.toString().substring(2)}',
                          ),
                    onTap: _pickDueDate,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('+ NOTES/REFERENCE NO.',
                                  style: TextStyle(
                                      color: brandBlue,
                                      fontWeight: FontWeight.w700)),
                            ),
                            SizedBox(
                              width: 150,
                              child: TextField(
                                controller: _receivedController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                textAlign: TextAlign.right,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Received',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _paymentRefController,
                          decoration: const InputDecoration(
                            hintText: 'Reference no. / notes',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Balance Due',
                          style:
                              TextStyle(color: Colors.black54, fontSize: 16)),
                      Text(
                        'AED ${_balanceDue.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: _saleBillAmount > 0 ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF96B8E4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'GENERATE SALE BILL AED ${_saleBillAmount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _paymentOption(String key, String label) {
    final selected = _paymentMode == key;
    return InkWell(
      onTap: () {
        setState(() {
          _paymentMode = key;
          if (key == 'cash' || key == 'card') {
            _receivedController.text = _saleBillAmount.toStringAsFixed(0);
          }
        });
      },
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? const Color(0xFF0B4F9E) : Colors.black45),
            ),
            child: selected
                ? const Center(
                    child: CircleAvatar(
                        radius: 4, backgroundColor: Color(0xFF0B4F9E)),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _InventoryPickerSheet extends StatefulWidget {
  const _InventoryPickerSheet({
    required this.businessId,
    required this.preselectedItems,
  });

  final int businessId;
  final List<Map<String, dynamic>> preselectedItems;

  @override
  State<_InventoryPickerSheet> createState() => _InventoryPickerSheetState();
}

class _InventoryPickerSheetState extends State<_InventoryPickerSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filtered = [];
  final Set<int> _selectedIds = {};
  final Map<int, int> _selectedQty = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    for (final item in widget.preselectedItems) {
      final id = item['id'] as int?;
      if (id == null) continue;
      _selectedIds.add(id);
      _selectedQty[id] = item['qty'] as int? ?? 1;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Api.getItems(
        businessId: widget.businessId,
        type: 'product',
      );
      final mapped =
          data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _items = mapped;
        _applyFilter('');
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _filtered = [];
        _loading = false;
      });
    }
  }

  void _applyFilter(String query) {
    final q = query.toLowerCase().trim();
    _filtered = _items.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      return q.isEmpty || name.contains(q);
    }).toList();
  }

  Future<void> _createItem() async {
    final data = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddItemScreen(type: 'product'),
      ),
    );

    if (data == null) return;

    await Api.createItem(
      businessId: widget.businessId,
      type: 'product',
      name: (data['name'] ?? '').toString(),
      unit: (data['unit'] ?? 'PCS').toString(),
      salePrice: (data['salePrice'] as num?)?.toDouble() ?? 0,
      purchasePrice: (data['purchasePrice'] as num?)?.toDouble() ?? 0,
      taxIncluded: (data['taxIncluded'] as bool?) ?? true,
      openingStock: (data['openingStock'] as int?) ?? 0,
      lowStockAlert: (data['lowStockAlert'] as int?) ?? 0,
      photoPath: data['photoPath'] as String?,
    );

    if (!mounted) return;
    await _load();
  }

  void _submit() {
    final selected = _items
        .where((item) => _selectedIds.contains(item['id'] as int))
        .map((item) {
      final photo = (item['photo_path'] ?? '').toString();
      return {
        'id': item['id'] as int,
        'name': (item['name'] ?? '').toString(),
        'price': double.tryParse((item['sale_price'] ?? '0').toString()) ?? 0,
        'currentStock': (item['current_stock'] ?? 0) as int,
        'photoUrl': photo.isEmpty
            ? null
            : 'https://eliteposs.com/financeserver/public/storage/$photo',
        'qty': _selectedQty[item['id'] as int] ?? 1,
      };
    }).toList();

    Navigator.pop(context, selected);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.92,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF032B63),
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Text('Sale Bill',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Items to your Invoice',
                    style: TextStyle(
                        fontSize: 24 / 1.2, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: brandBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _applyFilter(v)),
                          decoration: const InputDecoration(
                            hintText: 'Search for your created items',
                            border: InputBorder.none,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: brandBlue),
                        color: const Color(0xFFEAF2FF),
                      ),
                      child: const Text('Products',
                          style: TextStyle(color: brandBlue)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _createItem,
                  icon: const Icon(Icons.add, color: brandBlue),
                  label: const Text('CREATE NEW ITEM',
                      style: TextStyle(
                          color: brandBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _filtered[index];
                      final id = item['id'] as int;
                      final name = (item['name'] ?? '').toString();
                      final stock = (item['current_stock'] ?? 0) as int;
                      final price = double.tryParse(
                              (item['sale_price'] ?? '0').toString()) ??
                          0;
                      final photo = (item['photo_path'] ?? '').toString();
                      final selected = _selectedIds.contains(id);
                      final qty = _selectedQty[id] ?? 1;
                      return Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F4F7),
                                borderRadius: BorderRadius.circular(6),
                                image: photo.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(
                                            'https://eliteposs.com/financeserver/public/storage/$photo'),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: photo.isEmpty
                                  ? const Icon(Icons.inventory_2_outlined)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          fontSize: 20 / 1.3,
                                          fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Sales Price',
                                                style: TextStyle(
                                                    color: Colors.black54)),
                                            const SizedBox(height: 2),
                                            Text(
                                                'AED ${price.toStringAsFixed(0)}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Current Stock',
                                                style: TextStyle(
                                                    color: Colors.black54)),
                                            const SizedBox(height: 2),
                                            Text('$stock',
                                                style: TextStyle(
                                                    color: stock < 0
                                                        ? Colors.red
                                                        : Colors.black,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Text('Qty:',
                                          style:
                                              TextStyle(color: Colors.black54)),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            final next = qty - 1;
                                            _selectedQty[id] =
                                                next < 1 ? 1 : next;
                                          });
                                        },
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: Colors.black26),
                                          ),
                                          child: const Icon(Icons.remove,
                                              size: 14),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('$qty',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _selectedQty[id] = qty + 1;
                                          });
                                        },
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: Colors.black26),
                                          ),
                                          child:
                                              const Icon(Icons.add, size: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  if (selected) {
                                    _selectedIds.remove(id);
                                  } else {
                                    _selectedIds.add(id);
                                    _selectedQty[id] = _selectedQty[id] ?? 1;
                                  }
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(86, 44),
                                side: BorderSide(
                                    color: selected ? Colors.green : brandBlue),
                              ),
                              child: Text(
                                selected ? 'ADDED' : 'ADD',
                                style: TextStyle(
                                    color: selected ? Colors.green : brandBlue),
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B4F9E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('ADD ${_selectedIds.length} ITEM(S)'),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class _BillPartyPickerSheet extends StatefulWidget {
  const _BillPartyPickerSheet();

  @override
  State<_BillPartyPickerSheet> createState() => _BillPartyPickerSheetState();
}

class _BillPartyPickerSheetState extends State<_BillPartyPickerSheet> {
  final _queryController = TextEditingController();
  List<Map<String, dynamic>> _parties = [];
  List<Map<String, dynamic>> _filteredParties = [];
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');

    List<Map<String, dynamic>> parties = [];
    if (businessId != null) {
      try {
        final customers = await Api.getCustomers(businessId: businessId);
        parties =
            customers.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        parties = [];
      }
    }

    List<Contact> contacts = [];
    final status = await Permission.contacts.request();
    if (status.isGranted) {
      contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
      );
    }

    if (!mounted) return;
    setState(() {
      _parties = parties;
      _contacts = contacts;
      _applyFilter('');
      _loading = false;
    });
  }

  void _applyFilter(String query) {
    final q = query.toLowerCase().trim();
    _filteredParties = _parties.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final phone = (p['phone'] ?? '').toString().toLowerCase();
      return q.isEmpty || name.contains(q) || phone.contains(q);
    }).toList();

    _filteredContacts = _contacts.where((c) {
      final name = c.displayName.toLowerCase();
      final phone =
          c.phones.isNotEmpty ? c.phones.first.number.toLowerCase() : '';
      return q.isEmpty || name.contains(q) || phone.contains(q);
    }).toList();
  }

  Future<void> _openAddParty() async {
    final saved = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddCustomerScreen()),
    );
    if (saved == true) {
      await _load();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Add Party',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    _queryController.clear();
                    setState(() => _applyFilter(''));
                  },
                  icon: const Icon(Icons.close),
                ),
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    onChanged: (v) => setState(() => _applyFilter(v)),
                    decoration: InputDecoration(
                      hintText: 'Search by Party',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: brandBlue),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: brandBlue, style: BorderStyle.solid),
              ),
              child: const Icon(Icons.add, color: brandBlue),
            ),
            title: const Text('Add Party',
                style: TextStyle(color: brandBlue, fontSize: 20 / 1.5)),
            trailing: const Icon(Icons.chevron_right, color: brandBlue),
            onTap: _openAddParty,
          ),
          const Divider(height: 1),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Text('PARTIES',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                  ),
                  ..._filteredParties.map(
                    (p) => ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF0B4F9E),
                        child: Text(
                          (p['name'] ?? 'A')
                              .toString()
                              .trim()
                              .toUpperCase()
                              .substring(0, 1),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text((p['name'] ?? '').toString()),
                      subtitle: Text((p['phone'] ?? '').toString()),
                      onTap: () => Navigator.pop(context, {
                        'id': p['id'],
                        'name': (p['name'] ?? '').toString(),
                        'phone': (p['phone'] ?? '').toString(),
                      }),
                    ),
                  ),
                  const Divider(height: 1),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Text('PHONE BOOK',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                  ),
                  ..._filteredContacts.map(
                    (c) {
                      final phone =
                          c.phones.isNotEmpty ? c.phones.first.number : '';
                      final initials = c.displayName.isEmpty
                          ? '?'
                          : c.displayName
                              .split(' ')
                              .where((e) => e.isNotEmpty)
                              .take(2)
                              .map((e) => e[0].toUpperCase())
                              .join();
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF2A7DE1),
                          child: c.photo == null
                              ? Text(initials,
                                  style: const TextStyle(color: Colors.white))
                              : null,
                          backgroundImage:
                              c.photo != null ? MemoryImage(c.photo!) : null,
                        ),
                        title: Text(
                            c.displayName.isEmpty ? 'Unnamed' : c.displayName),
                        subtitle: Text(phone),
                        onTap: () => Navigator.pop(context, {
                          'id': null,
                          'name': c.displayName,
                          'phone': phone,
                        }),
                      );
                    },
                  ),
                ],
              ),
            )
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
