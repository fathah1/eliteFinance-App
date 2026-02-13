import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../routes.dart';
import 'item_detail_screen.dart';

class ItemData {
  ItemData({
    required this.id,
    required this.type,
    required this.name,
    required this.unit,
    required this.salePrice,
    required this.purchasePrice,
    required this.taxIncluded,
    required this.currentStock,
    required this.lowStockAlert,
    this.photoPath,
  });

  final int id;
  final String type; // product | service
  String name;
  String unit;
  double salePrice;
  double purchasePrice;
  bool taxIncluded;
  int currentStock;
  int lowStockAlert;
  String? photoPath;
}

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final List<ItemData> _items = [];
  String _tab = 'product';
  String _filter = 'all';
  String _query = '';
  int _nextId = 1;
  int? _activeBusinessServerId;
  bool _loading = true;

  List<ItemData> get _filtered {
    final list = _items.where((i) => i.type == _tab).toList();
    final filtered = _filter == 'low'
        ? list.where(_isLowStock).toList()
        : list;
    if (_query.isEmpty) return filtered;
    final q = _query.toLowerCase();
    return filtered.where((i) => i.name.toLowerCase().contains(q)).toList();
  }

  bool _isLowStock(ItemData item) {
    return item.currentStock <= item.lowStockAlert;
  }

  double get _totalStockValue {
    return _items
        .where((i) => i.type == _tab)
        .fold<double>(0, (sum, i) => sum + (i.currentStock * i.purchasePrice));
  }

  int get _lowStockCount {
    return _items.where((i) => i.type == _tab && _isLowStock(i)).length;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _activeBusinessServerId = prefs.getInt('active_business_server_id');
    if (_activeBusinessServerId == null) {
      await _autoSelectBusiness();
    }
    await _loadItems();
  }

  Future<void> _autoSelectBusiness() async {
    try {
      final businesses = await Api.getBusinesses();
      if (businesses.isEmpty) return;
      final first = businesses.first as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('active_business_server_id', first['id'] as int);
      _activeBusinessServerId = first['id'] as int;
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadItems() async {
    if (_activeBusinessServerId == null) {
      setState(() {
        _items.clear();
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await Api.getItems(
        businessId: _activeBusinessServerId!,
        type: _tab,
      );
      debugPrint(
        'Items fetch: business=$_activeBusinessServerId tab=$_tab count=${data.length}',
      );
      final list = data.map<ItemData>((e) {
        final map = Map<String, dynamic>.from(e as Map);
        final photo = (map['photo_path'] ?? '').toString();
        final photoUrl = photo.isEmpty
            ? null
            : 'https://eliteposs.com/financeserver/public/storage/$photo';
        final lastPurchase = map['last_purchase_price'];
        final purchase = lastPurchase ?? map['purchase_price'] ?? '0';
        return ItemData(
          id: map['id'] as int,
          type: (map['type'] ?? 'product').toString(),
          name: (map['name'] ?? '').toString(),
          unit: (map['unit'] ?? 'PCS').toString(),
          salePrice:
              double.tryParse((map['sale_price'] ?? '0').toString()) ?? 0,
          purchasePrice:
              double.tryParse(purchase.toString()) ?? 0,
          taxIncluded: (map['tax_included'] ?? true) == true ||
              (map['tax_included']?.toString() == '1'),
          currentStock: (map['current_stock'] ?? 0) as int,
          lowStockAlert: (map['low_stock_alert'] ?? 0) as int,
          photoPath: photoUrl,
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _loading = false;
        _nextId = list.isNotEmpty
            ? (list.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1)
            : 1;
      });
    } catch (_) {
      debugPrint('Items fetch failed.');
      if (!mounted) return;
      setState(() {
        _items.clear();
        _loading = false;
      });
    }
  }

  Future<void> _addItem() async {
    final result = await Navigator.push(
      context,
      AppRoutes.onGenerateRoute(
        RouteSettings(
          name: AppRoutes.addItem,
          arguments: {'type': _tab},
        ),
      ),
    );
    if (result is Map<String, dynamic>) {
      if (_activeBusinessServerId == null) return;
      if (result['id'] != null) {
        final updated = await Api.updateItem(
          itemId: result['id'] as int,
          name: result['name'] as String,
          unit: result['unit'] as String,
          taxIncluded: result['taxIncluded'] as bool,
          salePrice: result['salePrice'] as double,
          purchasePrice: result['purchasePrice'] as double,
          lowStockAlert: result['lowStockAlert'] as int,
          photoPath: result['photoPath'] as String?,
        );
        final photo = (updated['photo_path'] ?? '').toString();
        final photoUrl = photo.isEmpty
            ? null
            : 'https://eliteposs.com/financeserver/public/storage/$photo';
        setState(() {
          final idx = _items.indexWhere((i) => i.id == updated['id']);
          if (idx != -1) {
            _items[idx]
              ..name = (updated['name'] ?? _items[idx].name).toString()
              ..unit = (updated['unit'] ?? _items[idx].unit).toString()
              ..salePrice = double.tryParse(
                      (updated['sale_price'] ?? _items[idx].salePrice)
                          .toString()) ??
                  _items[idx].salePrice
              ..purchasePrice = double.tryParse(
                      (updated['purchase_price'] ?? _items[idx].purchasePrice)
                          .toString()) ??
                  _items[idx].purchasePrice
              ..lowStockAlert = int.tryParse(
                      (updated['low_stock_alert'] ??
                              _items[idx].lowStockAlert)
                          .toString()) ??
                  _items[idx].lowStockAlert
              ..currentStock = int.tryParse(
                      (updated['current_stock'] ?? _items[idx].currentStock)
                          .toString()) ??
                  _items[idx].currentStock
              ..photoPath = photoUrl;
          }
        });
        await _loadItems();
      } else {
        final created = await Api.createItem(
          businessId: _activeBusinessServerId!,
          type: result['type'] as String,
          name: result['name'] as String,
          unit: result['unit'] as String,
          salePrice: result['salePrice'] as double,
          purchasePrice: result['purchasePrice'] as double,
          taxIncluded: result['taxIncluded'] as bool,
          openingStock: result['openingStock'] as int,
          lowStockAlert: result['lowStockAlert'] as int,
          photoPath: result['photoPath'] as String?,
        );
          final photo = (created['photo_path'] ?? '').toString();
          final photoUrl = photo.isEmpty
              ? null
              : 'https://eliteposs.com/financeserver/public/storage/$photo';
        setState(() {
          _items.add(ItemData(
            id: created['id'] as int,
            type: (created['type'] ?? 'product').toString(),
            name: (created['name'] ?? '').toString(),
            unit: (created['unit'] ?? 'PCS').toString(),
            salePrice: double.tryParse(
                    (created['sale_price'] ?? '0').toString()) ??
                0,
            purchasePrice: double.tryParse(
                    (created['purchase_price'] ?? '0').toString()) ??
                0,
            taxIncluded: (created['tax_included'] ?? true) == true ||
                (created['tax_included']?.toString() == '1'),
            currentStock: int.tryParse(
                    (created['current_stock'] ?? 0).toString()) ??
                0,
            lowStockAlert: int.tryParse(
                    (created['low_stock_alert'] ?? 0).toString()) ??
                0,
            photoPath: photoUrl,
          ));
        });
        await _loadItems();
      }
    }
  }

  Future<void> _openStockSheet(ItemData item, String type) async {
    final qtyController = TextEditingController(text: '0');
    final priceController = TextEditingController(
      text: type == 'in'
          ? item.purchasePrice.toStringAsFixed(0)
          : item.salePrice.toStringAsFixed(0),
    );
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(builder: (context, setSheet) {
          final title = type == 'in' ? 'Stock In' : 'Stock Out';
          final subtitle = type == 'in'
              ? 'Enter quantity of purchased items'
              : 'Enter quantity of sold items';
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(subtitle,
                      style: const TextStyle(color: Colors.black54)),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 32),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(item.unit, style: const TextStyle(fontSize: 20)),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText:
                              type == 'in' ? 'Purchase Price' : 'Sale Price',
                          prefixText: 'AED ',
                          filled: true,
                          fillColor: Colors.white,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setSheet(() => selectedDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat('dd MMM yy').format(selectedDate)),
                              const Icon(Icons.expand_more),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      final note = await showDialog<String>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Add Notes'),
                            content: TextField(
                              controller: noteController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Add notes (optional)',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, null),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(
                                  context,
                                  noteController.text.trim(),
                                ),
                                child: const Text('Save'),
                              ),
                            ],
                          );
                        },
                      );
                      if (note != null) {
                        noteController.text = note;
                      }
                    },
                    child: const Text('Add Notes (Optional)'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final qty =
                          int.tryParse(qtyController.text.trim()) ?? 0;
                      if (qty <= 0) return;
                      final price =
                          double.tryParse(priceController.text.trim()) ?? 0;
                      final result = await Api.addItemStock(
                        itemId: item.id,
                        type: type,
                        quantity: qty,
                        price: price,
                        date: DateFormat('yyyy-MM-dd').format(selectedDate),
                        note: noteController.text.trim().isEmpty
                            ? null
                            : noteController.text.trim(),
                      );
                      final updated = result['item'] as Map<String, dynamic>;
                      setState(() {
                        item.currentStock = int.tryParse(
                                (updated['current_stock'] ??
                                        item.currentStock)
                                    .toString()) ??
                            item.currentStock;
                        if (type == 'in') {
                          item.purchasePrice = double.tryParse(
                                  (updated['purchase_price'] ??
                                          item.purchasePrice)
                                      .toString()) ??
                              item.purchasePrice;
                        }
                      });
                      await _loadItems();
                      if (mounted) Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B4F9E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(type == 'in' ? 'STOCK IN' : 'STOCK OUT'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: const Text('Items'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'items_add_fab',
        onPressed: _addItem,
        backgroundColor: const Color(0xFF0B4F9E),
        icon: const Icon(Icons.add_box, color: Colors.white),
        label: const Text(
          'ADD PRODUCT',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: brandBlue,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    _TopTab(
                      label: 'PRODUCTS',
                      selected: true,
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
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
                            children: [
                              Text('AED ${_totalStockValue.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              const Text('Total Stock value',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Text('$_lowStockCount',
                                  style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              const Text('Low Stock Items',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: InkWell(
                          onTap: () {},
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Text('VIEW REPORTS',
                                    style: TextStyle(
                                        color: brandBlue,
                                        fontWeight: FontWeight.bold)),
                                Icon(Icons.chevron_right, color: brandBlue),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v.trim()),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search Items',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: const [
                    Icon(Icons.sort, color: Color(0xFF0B4F9E)),
                    SizedBox(height: 2),
                    Text('Sort', style: TextStyle(fontSize: 11)),
                  ],
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All Items',
                  selected: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 12),
                _FilterChip(
                  label: 'Low Stock',
                  selected: _filter == 'low',
                  showDot: _lowStockCount > 0,
                  onTap: () => setState(() => _filter = 'low'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('MY ITEMS',
                    style: TextStyle(color: Colors.black54)),
                Text('${_filtered.length} ITEMS ADDED',
                    style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('No items yet.'))
                    : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final item = _filtered[index];
                      return InkWell(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItemDetailScreen(item: item),
                            ),
                          );
                          await _loadItems();
                        },
                        child: Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF2F7),
                                      borderRadius: BorderRadius.circular(8),
                                      image: item.photoPath != null
                                          ? DecorationImage(
                                              image: item.photoPath!
                                                      .startsWith('http')
                                                  ? NetworkImage(
                                                      item.photoPath!)
                                                  : FileImage(
                                                          File(item.photoPath!))
                                                      as ImageProvider,
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: item.photoPath == null
                                        ? const Icon(Icons.inventory_2_outlined)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 6),
                                        Text('Unit: ${item.unit}',
                                            style: const TextStyle(
                                                color: Colors.black54,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  if (_isLowStock(item))
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFDEDED),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Text(
                                        'Low Stock',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('Sale Price (AED)',
                                            style: TextStyle(fontSize: 12)),
                                        const SizedBox(height: 4),
                                        Text(
                                          'AED ${item.salePrice.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('Current Stock',
                                            style: TextStyle(fontSize: 12)),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.currentStock.toString(),
                                          style: TextStyle(
                                            color: _isLowStock(item)
                                                ? Colors.red
                                                : Colors.black,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _openStockSheet(item, 'in'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.green,
                                      side: const BorderSide(
                                          color: Colors.green),
                                    ),
                                    child: const Text('+ IN'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: () => _openStockSheet(item, 'out'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side:
                                          const BorderSide(color: Colors.red),
                                    ),
                                    child: const Text('- OUT'),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TopTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 3,
            width: 60,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFFFB020) : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showDot;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? const Color(0xFF0B4F9E) : Colors.black12,
          ),
          color: selected ? const Color(0xFFE9EEF9) : Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF0B4F9E) : Colors.black87,
              ),
            ),
            if (showDot)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
