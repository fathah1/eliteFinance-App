import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';

class ExpenseDraft {
  ExpenseDraft({
    required this.saved,
    this.expense,
    this.deleted = false,
  });

  final bool saved;
  final bool deleted;
  final Map<String, dynamic>? expense;
}

class _ExpenseItem {
  _ExpenseItem({
    required this.itemId,
    required this.name,
    required this.qty,
    required this.price,
  });

  final int itemId;
  String name;
  int qty;
  double price;

  double get lineTotal => qty * price;

  Map<String, dynamic> toJson() => {
        'item_id': itemId,
        'name': name,
        'qty': qty,
        'price': price,
      };
}

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({
    super.key,
    required this.expenseNumber,
    this.expense,
  });

  final int expenseNumber;
  final Map<String, dynamic>? expense;

  bool get isEdit => expense != null;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _amountController = TextEditingController();
  DateTime _date = DateTime.now();
  int _expenseNumber = 1;
  int? _categoryId;
  String? _categoryName;
  final List<_ExpenseItem> _items = [];
  bool _saving = false;

  double get _itemsTotal =>
      _items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  double get _expenseAmount {
    if (_items.isNotEmpty) return _itemsTotal;
    return double.tryParse(_amountController.text.trim()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _expenseNumber = widget.expenseNumber;
    _loadInitial();
  }

  void _loadInitial() {
    final initial = widget.expense;
    if (initial == null) return;

    _expenseNumber =
        _toInt(initial['expense_number'], fallback: _expenseNumber);
    _date =
        DateTime.tryParse((initial['date'] ?? '').toString()) ?? DateTime.now();
    _categoryId = _toNullableInt(initial['expense_category_id']);
    _categoryName = (initial['category_name'] ?? '').toString().trim().isEmpty
        ? null
        : (initial['category_name'] ?? '').toString().trim();

    final items = (initial['items'] as List?) ?? const [];
    _items
      ..clear()
      ..addAll(items.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return _ExpenseItem(
          itemId: _toInt(m['item_id'], fallback: _toInt(m['id'])),
          name: (m['name'] ?? '').toString(),
          qty: _toInt(m['qty'], fallback: 1),
          price: _toDouble(m['price']),
        );
      }).where((e) => e.itemId > 0));

    _amountController.text = _toDouble(initial['amount']).toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  int? _toNullableInt(dynamic value) {
    final n = _toInt(value, fallback: 0);
    return n > 0 ? n : null;
  }

  double _toDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  String _toApiDate(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
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

  Future<void> _editExpenseNumber() async {
    final controller = TextEditingController(text: '$_expenseNumber');
    final value = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Expense Number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Enter expense number'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v <= 0) return;
              Navigator.pop(context, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    setState(() => _expenseNumber = value);
  }

  Future<void> _openCategoryPicker() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CategoryPickerSheet(),
    );
    if (selected == null) return;
    setState(() {
      _categoryId = _toNullableInt(selected['id']);
      _categoryName = (selected['name'] ?? '').toString();
    });
  }

  Future<void> _openItemsPicker() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    if (businessId == null || !mounted) return;

    final selected = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ExpenseItemsPickerSheet(
        businessId: businessId,
        preselected: _items
            .map((e) => {
                  'item_id': e.itemId,
                  'name': e.name,
                  'qty': e.qty,
                  'price': e.price,
                })
            .toList(),
      ),
    );
    if (selected == null) return;

    setState(() {
      _items
        ..clear()
        ..addAll(
          selected.map(
            (e) => _ExpenseItem(
              itemId: _toInt(e['item_id']),
              name: (e['name'] ?? '').toString(),
              qty: _toInt(e['qty'], fallback: 1),
              price: _toDouble(e['price']),
            ),
          ),
        );
      _amountController.text = _expenseAmount.toStringAsFixed(0);
    });
  }

  Future<void> _save() async {
    if (_expenseAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter expense amount')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final businessId = prefs.getInt('active_business_server_id');
    if (businessId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active business selected')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final payloadItems = _items.map((e) => e.toJson()).toList();
      final expense = widget.isEdit
          ? await Api.updateExpense(
              id: _toInt(widget.expense!['id']),
              expenseNumber: _expenseNumber,
              date: _toApiDate(_date),
              categoryId: _categoryId,
              categoryName: _categoryName,
              manualAmount: _toDouble(_amountController.text.trim()),
              items: payloadItems,
            )
          : await Api.createExpense(
              businessId: businessId,
              expenseNumber: _expenseNumber,
              date: _toApiDate(_date),
              categoryId: _categoryId,
              categoryName: _categoryName,
              manualAmount: _toDouble(_amountController.text.trim()),
              items: payloadItems,
            );
      if (!mounted) return;
      Navigator.pop(context, ExpenseDraft(saved: true, expense: expense));
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
    const brandBlue = Color(0xFF0B4F9E);
    final dateText =
        '${_date.day.toString().padLeft(2, '0')} ${_month(_date.month)} ${_date.year.toString().substring(2)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Text(widget.isEdit ? 'Edit Expense' : 'Add Expense'),
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
                      const Text('Expense No.',
                          style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '$_expenseNumber',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _editExpenseNumber,
                            child: const Icon(Icons.edit, color: brandBlue),
                          ),
                        ],
                      )
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
                )
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(_categoryName == null ? 'Category' : _categoryName!),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openCategoryPicker,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(_items.isEmpty
                      ? 'Add Expense Items (Optional)'
                      : '${_items.length} Item'),
                  trailing: Text(
                    _items.isEmpty ? '' : 'EDIT OR ADD ITEMS',
                    style: const TextStyle(
                      color: brandBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: _openItemsPicker,
                ),
                const SizedBox(
                  width: double.infinity,
                  child: ColoredBox(
                    color: Color(0xFFF6E4A8),
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                          'Expense items will not affect your inventory items'),
                    ),
                  ),
                ),
                if (_items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Column(
                      children: _items
                          .map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          '${e.qty}.0 x AED ${e.price.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                              color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text('AED ${e.lineTotal.toStringAsFixed(0)}'),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Expense Amount',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                if (_items.isNotEmpty)
                  Text(
                    'AED ${_expenseAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w700),
                  )
                else
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: _saving || _expenseAmount <= 0 ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4F9E),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF96B8E4),
              ),
              child: Text(
                widget.isEdit
                    ? 'SAVE EXPENSE: AED ${_expenseAmount.toStringAsFixed(0)}'
                    : 'SAVE EXPENSE: AED ${_expenseAmount.toStringAsFixed(0)}',
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet();

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  int? _businessId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _businessId = prefs.getInt('active_business_server_id');
    if (_businessId == null) {
      if (!mounted) return;
      setState(() {
        _categories = [];
        _filtered = [];
        _loading = false;
      });
      return;
    }
    try {
      final rows = await Api.getExpenseCategories(businessId: _businessId!);
      final list =
          rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _categories = list;
        _applyFilter('');
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categories = [];
        _filtered = [];
        _loading = false;
      });
    }
  }

  void _applyFilter(String q) {
    final query = q.toLowerCase().trim();
    _filtered = _categories.where((c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      return query.isEmpty || name.contains(query);
    }).toList();
  }

  Future<void> _createCategory() async {
    if (_businessId == null) return;
    final controller = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final inset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add New Category',
                  style:
                      TextStyle(fontSize: 40 / 2, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Category Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('SAVE'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('CANCEL'),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
    if (created != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;

    try {
      final row = await Api.createExpenseCategory(
        businessId: _businessId!,
        name: name,
      );
      if (!mounted) return;
      setState(() {
        _categories.insert(0, row);
        _applyFilter(_query.text);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          ListTile(
            title: const Text(
              'Add Category',
              style: TextStyle(fontSize: 40 / 2, fontWeight: FontWeight.w700),
            ),
            trailing: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _query,
              onChanged: (v) => setState(() => _applyFilter(v)),
              decoration: const InputDecoration(
                hintText: 'Search Category',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          ListTile(
            title: const Text(
              '+ CREATE A NEW CATEGORY',
              style: TextStyle(color: brandBlue, fontWeight: FontWeight.w700),
            ),
            onTap: _createCategory,
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final c = _filtered[index];
                      return ListTile(
                        title: Text((c['name'] ?? '').toString()),
                        trailing: const Icon(Icons.radio_button_unchecked),
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}

class _ExpenseItemsPickerSheet extends StatefulWidget {
  const _ExpenseItemsPickerSheet({
    required this.businessId,
    required this.preselected,
  });

  final int businessId;
  final List<Map<String, dynamic>> preselected;

  @override
  State<_ExpenseItemsPickerSheet> createState() =>
      _ExpenseItemsPickerSheetState();
}

class _ExpenseItemsPickerSheetState extends State<_ExpenseItemsPickerSheet> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filtered = [];
  final Map<int, int> _qty = {};
  bool _loading = true;
  bool _showSelectedOnly = false;

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  double _toDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    for (final p in widget.preselected) {
      final id = _toInt(p['item_id']);
      if (id <= 0) continue;
      _qty[id] = _toInt(p['qty'], fallback: 1);
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Api.getExpenseItems(businessId: widget.businessId);
      final list =
          rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _applyFilter('');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Load failed: $e')));
      setState(() {
        _items = [];
        _filtered = [];
        _loading = false;
      });
    }
  }

  void _applyFilter(String q) {
    final query = q.toLowerCase().trim();
    _filtered = _items.where((it) {
      final name = (it['name'] ?? '').toString().toLowerCase();
      final id = _toInt(it['id']);
      final selected = (_qty[id] ?? 0) > 0;
      if (_showSelectedOnly && !selected) return false;
      return query.isEmpty || name.contains(query);
    }).toList();
  }

  int get _selectedCount => _qty.values.where((e) => e > 0).length;

  double get _selectedTotal {
    double sum = 0;
    for (final item in _items) {
      final id = _toInt(item['id']);
      final q = _qty[id] ?? 0;
      if (q <= 0) continue;
      sum += q * _toDouble(item['rate']);
    }
    return sum;
  }

  Future<void> _openCreateOrEdit({Map<String, dynamic>? item}) async {
    final nameController =
        TextEditingController(text: (item?['name'] ?? '').toString());
    final rateController = TextEditingController(
      text: item == null ? '' : _toDouble(item['rate']).toStringAsFixed(0),
    );

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final inset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + inset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  item == null
                      ? 'Create a new expense item'
                      : 'Edit expense item',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: rateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Item Rate',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4F9E),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('SAVE'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('CANCEL'),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
    if (ok != true) return;

    final name = nameController.text.trim();
    final rate = double.tryParse(rateController.text.trim()) ?? 0;
    if (name.isEmpty || rate <= 0) return;

    try {
      if (item == null) {
        final created = await Api.createExpenseItem(
          businessId: widget.businessId,
          name: name,
          rate: rate,
        );
        if (!mounted) return;
        setState(() {
          _items.insert(0, created);
          _qty[_toInt(created['id'])] = 1;
          _applyFilter(_query.text);
        });
      } else {
        final updated = await Api.updateExpenseItem(
          id: _toInt(item['id']),
          name: name,
          rate: rate,
        );
        if (!mounted) return;
        setState(() {
          final index =
              _items.indexWhere((e) => _toInt(e['id']) == _toInt(item['id']));
          if (index >= 0) {
            _items[index] = updated;
          }
          _applyFilter(_query.text);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  void _submit() {
    final selected = _items.where((it) {
      final id = _toInt(it['id']);
      return (_qty[id] ?? 0) > 0;
    }).map((it) {
      final id = _toInt(it['id']);
      return {
        'item_id': id,
        'name': (it['name'] ?? '').toString(),
        'qty': _qty[id] ?? 1,
        'price': _toDouble(it['rate']),
      };
    }).toList();
    Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Column(
        children: [
          ListTile(
            title: const Text(
              'Add Expense Items',
              style: TextStyle(fontSize: 40 / 2, fontWeight: FontWeight.w700),
            ),
            trailing: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          const SizedBox(
            width: double.infinity,
            child: ColoredBox(
              color: Color(0xFFF6E4A8),
              child: Padding(
                padding: EdgeInsets.all(10),
                child:
                    Text('Expense items will not affect your inventory items'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              onChanged: (v) => setState(() => _applyFilter(v)),
              decoration: const InputDecoration(
                hintText: 'Search for Expense Items',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          ListTile(
            title: const Text(
              '+ CREATE A NEW EXPENSE ITEM',
              style: TextStyle(color: brandBlue, fontWeight: FontWeight.w700),
            ),
            onTap: _openCreateOrEdit,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final item = _filtered[index];
                      final id = _toInt(item['id']);
                      final qty = _qty[id] ?? 0;
                      final price = _toDouble(item['rate']);
                      final selected = qty > 0;

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (item['name'] ?? '').toString(),
                                    style: const TextStyle(
                                      fontSize: 31 / 2,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text('PRICE',
                                      style: TextStyle(color: Colors.black54)),
                                  Text(
                                    'AED ${price.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 31 / 2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () => _openCreateOrEdit(item: item),
                                    child: const Text(
                                      'EDIT ITEM',
                                      style: TextStyle(
                                        color: brandBlue,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            selected
                                ? Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: brandBlue),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        InkWell(
                                          onTap: () => setState(() {
                                            final next = qty - 1;
                                            _qty[id] = next < 0 ? 0 : next;
                                            _applyFilter(_query.text);
                                          }),
                                          child: const SizedBox(
                                            width: 54,
                                            height: 52,
                                            child: Icon(Icons.remove),
                                          ),
                                        ),
                                        Container(
                                          width: 58,
                                          alignment: Alignment.center,
                                          child: Text(
                                            '$qty',
                                            style: const TextStyle(
                                                fontSize: 30 / 2),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => setState(() {
                                            _qty[id] = qty + 1;
                                          }),
                                          child: const SizedBox(
                                            width: 54,
                                            height: 52,
                                            child: Icon(Icons.add),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : SizedBox(
                                    width: 170,
                                    child: OutlinedButton(
                                      onPressed: () => setState(() {
                                        _qty[id] = 1;
                                      }),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 52),
                                      ),
                                      child: const Text(
                                        'ADD',
                                        style: TextStyle(
                                          fontSize: 34 / 2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Expanded(child: Text('Show selected items only')),
                Switch(
                  value: _showSelectedOnly,
                  onChanged: (v) => setState(() {
                    _showSelectedOnly = v;
                    _applyFilter(_query.text);
                  }),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$_selectedCount Item',
                            style: const TextStyle(fontSize: 36 / 2)),
                        Text(
                          'AED ${_selectedTotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 36 / 2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 56),
                      ),
                      child: const Text(
                        'CONTINUE',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                      ),
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
