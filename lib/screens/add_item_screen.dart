import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AddItemScreen extends StatefulWidget {
  final String type; // product | service
  final Map<String, dynamic>? initial;
  const AddItemScreen({super.key, required this.type, this.initial});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _nameController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _openingStockController = TextEditingController();
  final _lowStockController = TextEditingController();

  String _unit = 'PCS';
  bool _taxIncluded = true;
  String? _photoPath;
  int? _itemId;

  @override
  void dispose() {
    _nameController.dispose();
    _salePriceController.dispose();
    _purchasePriceController.dispose();
    _openingStockController.dispose();
    _lowStockController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _photoPath = file.path);
  }

  bool get _canSave => _nameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _itemId = initial['id'] as int?;
      _nameController.text = (initial['name'] ?? '').toString();
      _unit = (initial['unit'] ?? 'PCS').toString();
      _salePriceController.text =
          (initial['sale_price'] ?? initial['salePrice'] ?? '').toString();
      _purchasePriceController.text =
          (initial['purchase_price'] ?? initial['purchasePrice'] ?? '')
              .toString();
      _openingStockController.text =
          (initial['opening_stock'] ?? initial['openingStock'] ?? '')
              .toString();
      _lowStockController.text =
          (initial['low_stock_alert'] ?? initial['lowStockAlert'] ?? '')
              .toString();
      _taxIncluded = (initial['tax_included'] ?? initial['taxIncluded'] ?? true) ==
              true ||
          (initial['tax_included']?.toString() == '1');
      final photo = (initial['photo_path'] ?? initial['photoPath'] ?? '')
          .toString();
      _photoPath = photo.isEmpty ? null : photo;
    }
  }

  void _save() {
    if (!_canSave) return;
    final salePrice =
        double.tryParse(_salePriceController.text.trim()) ?? 0;
    final purchasePrice =
        double.tryParse(_purchasePriceController.text.trim()) ?? 0;
    final openingStock =
        int.tryParse(_openingStockController.text.trim()) ?? 0;
    final lowStock = int.tryParse(_lowStockController.text.trim()) ?? 0;

    Navigator.pop(context, {
      'type': widget.type,
      'id': _itemId,
      'name': _nameController.text.trim(),
      'unit': _unit,
      'salePrice': salePrice,
      'purchasePrice': purchasePrice,
      'taxIncluded': _taxIncluded,
      'openingStock': openingStock,
      'lowStockAlert': lowStock,
      'photoPath': _photoPath,
    });
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: const Text('Add Item'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'Enter item name here*',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: _pickPhoto,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: _photoPath == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.camera_alt_outlined),
                            SizedBox(height: 4),
                            Text('Photo', style: TextStyle(fontSize: 12)),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _photoPath!.startsWith('http')
                              ? Image.network(_photoPath!, fit: BoxFit.cover)
                              : Image.file(
                                  File(_photoPath!),
                                  fit: BoxFit.cover,
                                ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Unit', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _unit,
            items: const [
              DropdownMenuItem(value: 'PCS', child: Text('PCS')),
              DropdownMenuItem(value: 'KG', child: Text('KG')),
              DropdownMenuItem(value: 'L', child: Text('L')),
              DropdownMenuItem(value: 'BOX', child: Text('BOX')),
            ],
            onChanged: (v) => setState(() => _unit = v ?? 'PCS'),
            decoration: const InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _salePriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sale Price',
                    prefixText: 'AED ',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _purchasePriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Purchase Price',
                    prefixText: 'AED ',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _taxIncluded,
            onChanged: (v) => setState(() => _taxIncluded = v),
            title: const Text('Tax included'),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _openingStockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Opening Stock',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lowStockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Low Stock Alert',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Text('As of date', style: TextStyle(color: Colors.black54)),
              SizedBox(width: 8),
              Text('Today', style: TextStyle(color: Color(0xFF0B4F9E))),
              SizedBox(width: 6),
              Icon(Icons.edit, size: 16, color: Color(0xFF0B4F9E)),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _canSave ? _save : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B4F9E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('SAVE ITEM'),
          ),
        ],
      ),
    );
  }
}
