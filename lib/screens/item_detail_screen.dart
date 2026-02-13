import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../routes.dart';
import 'items_screen.dart';

class ItemDetailScreen extends StatefulWidget {
  final ItemData item;
  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  List<Map<String, dynamic>> _movements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Api.getItemMovements(itemId: widget.item.id);
      final list =
          data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      int running = widget.item.currentStock;
      for (final m in list) {
        m['running_balance'] = running;
        final type = (m['type'] ?? '').toString();
        final qty = int.tryParse((m['quantity'] ?? '0').toString()) ?? 0;
        if (type == 'in') {
          running -= qty;
        } else {
          running += qty;
        }
      }
      if (!mounted) return;
      setState(() {
        _movements = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _movements = [];
        _loading = false;
      });
    }
  }

  Future<void> _openStockSheet(String type) async {
    final qtyController = TextEditingController(text: '0');
    final priceController = TextEditingController(
      text: type == 'in'
          ? widget.item.purchasePrice.toStringAsFixed(0)
          : widget.item.salePrice.toStringAsFixed(0),
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
                    Text(widget.item.unit,
                        style: const TextStyle(fontSize: 20)),
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
                              Text(
                                  DateFormat('dd MMM yy').format(selectedDate)),
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
                        itemId: widget.item.id,
                        type: type,
                        quantity: qty,
                        price: price,
                        date: DateFormat('yyyy-MM-dd').format(selectedDate),
                        note: noteController.text.trim().isEmpty
                            ? null
                            : noteController.text.trim(),
                      );
                      final updated = result['item'] as Map<String, dynamic>;
                      widget.item.currentStock = int.tryParse(
                              (updated['current_stock'] ?? widget.item.currentStock)
                                  .toString()) ??
                          widget.item.currentStock;
                      if (type == 'in') {
                        widget.item.purchasePrice = double.tryParse(
                                (updated['purchase_price'] ??
                                        widget.item.purchasePrice)
                                    .toString()) ??
                            widget.item.purchasePrice;
                      }
                      if (mounted) {
                        Navigator.pop(context, true);
                        await _load();
                        setState(() {});
                      }
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
    final item = widget.item;
    final isLow = item.currentStock <= item.lowStockAlert;
    double lastPurchase = item.purchasePrice;
    for (final m in _movements) {
      if ((m['type'] ?? '').toString() == 'in') {
        lastPurchase =
            double.tryParse((m['price'] ?? '0').toString()) ?? lastPurchase;
        break;
      }
    }
    final stockValue = item.currentStock * lastPurchase;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(''),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                AppRoutes.onGenerateRoute(
                  RouteSettings(
                    name: AppRoutes.addItem,
                    arguments: {
                      'type': item.type,
                      'initial': {
                        'id': item.id,
                        'name': item.name,
                        'unit': item.unit,
                        'sale_price': item.salePrice,
                        'purchase_price': item.purchasePrice,
                        'opening_stock': item.currentStock,
                        'low_stock_alert': item.lowStockAlert,
                        'photo_path': item.photoPath ?? '',
                      }
                    },
                  ),
                ),
              );
              if (result is Map<String, dynamic>) {
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
                item.name = (updated['name'] ?? item.name).toString();
                item.unit = (updated['unit'] ?? item.unit).toString();
                item.salePrice = double.tryParse(
                        (updated['sale_price'] ?? item.salePrice).toString()) ??
                    item.salePrice;
                item.purchasePrice = double.tryParse(
                        (updated['purchase_price'] ?? item.purchasePrice)
                            .toString()) ??
                    item.purchasePrice;
                item.lowStockAlert = int.tryParse(
                        (updated['low_stock_alert'] ?? item.lowStockAlert)
                            .toString()) ??
                    item.lowStockAlert;
                final photo = (updated['photo_path'] ?? '').toString();
                item.photoPath = photo.isEmpty
                    ? item.photoPath
                    : 'https://eliteposs.com/financeserver/public/storage/$photo';
                if (mounted) setState(() {});
                Navigator.pop(context, true);
              }
            },
            icon: const Icon(Icons.edit, color: Color(0xFF0B4F9E)),
            label: const Text(
              'EDIT PRODUCT',
              style: TextStyle(color: Color(0xFF0B4F9E)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Item Name',
                              style: TextStyle(color: Colors.black54)),
                          const SizedBox(height: 4),
                          Text(
                            item.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          if (isLow)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDEDED),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Low Stock',
                                style:
                                    TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF2F7),
                        borderRadius: BorderRadius.circular(8),
                        image: item.photoPath != null
                            ? DecorationImage(
                                image: item.photoPath!.startsWith('http')
                                    ? NetworkImage(item.photoPath!)
                                    : FileImage(File(item.photoPath!))
                                        as ImageProvider,
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: item.photoPath == null
                          ? const Icon(Icons.inventory_2_outlined)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _DetailCell(
                      label: 'Sale Price',
                      value: 'AED ${item.salePrice.toStringAsFixed(0)}',
                    ),
                    _DetailCell(
                      label: 'Last Purchase Price',
                      value: 'AED ${lastPurchase.toStringAsFixed(0)}',
                    ),
                    _DetailCell(
                      label: 'Stock Quantity',
                      value: '${item.currentStock} ${item.unit}',
                      valueColor: isLow ? Colors.red : Colors.black,
                    ),
                  ],
                ),
                Row(
                  children: [
                    _DetailCell(
                      label: 'Stock Value',
                      value: 'AED ${stockValue.toStringAsFixed(0)}',
                    ),
                    _DetailCell(
                      label: 'Unit',
                      value: item.unit,
                    ),
                    _DetailCell(
                      label: 'Low Stock',
                      value: '${item.lowStockAlert} ${item.unit}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _movements.isEmpty
                    ? const Center(child: Text('No stock movements yet.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _movements.length,
                        itemBuilder: (context, index) {
                          final m = _movements[index];
                          final type = (m['type'] ?? '').toString();
                          final qty = (m['quantity'] ?? 0).toString();
                          final price = (m['price'] ?? 0).toString();
                          final date = (m['created_at'] ?? m['date'] ?? '').toString();
                          final balance =
                              (m['running_balance'] ?? item.currentStock)
                                  .toString();
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(date),
                                        const SizedBox(height: 6),
                                        Text(
                                            'Stock Balance $balance ${item.unit}'),
                                      ],
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 110,
                                  color: type == 'out'
                                      ? const Color(0xFFFDEDED)
                                      : const Color(0xFFE9F7EF),
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      Text(
                                        type == 'out' ? 'Out' : 'In',
                                        style: TextStyle(
                                          color: type == 'out'
                                              ? Colors.red
                                              : Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('$qty ${item.unit}'),
                                      const SizedBox(height: 4),
                                      Text('AED $price'),
                                    ],
                                  ),
                                ),
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
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _openStockSheet('in'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('STOCK IN'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _openStockSheet('out'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('STOCK OUT'),
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

class _DetailCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailCell({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: Color(0xFFE6E6E6)),
            bottom: BorderSide(color: Color(0xFFE6E6E6)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: valueColor ?? Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
