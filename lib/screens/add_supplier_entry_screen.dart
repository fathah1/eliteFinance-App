import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';

class AddSupplierEntryScreen extends StatefulWidget {
  final int supplierId;
  final Map<String, dynamic>? transaction;
  final String? initialType;
  const AddSupplierEntryScreen({
    super.key,
    required this.supplierId,
    this.transaction,
    this.initialType,
  });

  @override
  State<AddSupplierEntryScreen> createState() => _AddSupplierEntryScreenState();
}

class _AddSupplierEntryScreenState extends State<AddSupplierEntryScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _type = 'CREDIT';
  DateTime _date = DateTime.now();
  String? _error;
  File? _attachment;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    if (t != null) {
      _amountController.text = (t['amount'] ?? '').toString();
      _noteController.text = (t['note'] ?? '').toString();
      _type = (t['type'] ?? 'CREDIT').toString();
      final raw = t['created_at']?.toString();
      final parsed = raw != null ? DateTime.tryParse(raw) : null;
      if (parsed != null) _date = parsed;
    } else if (widget.initialType != null) {
      _type = widget.initialType!;
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      _attachment = File(picked.path);
    });
  }

  Future<int?> _getActiveBusinessServerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('active_business_server_id');
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _error = 'Enter a valid amount.';
      });
      return;
    }

    final businessId = await _getActiveBusinessServerId();
    if (businessId == null) {
      setState(() {
        _error = 'Please select a business first.';
      });
      return;
    }

    final createdAt = _date.toIso8601String();
    try {
      if (widget.transaction == null) {
        await Api.createSupplierTransaction(
          businessId: businessId,
          supplierId: widget.supplierId,
          amount: amount,
          type: _type,
          note: _noteController.text.trim(),
          createdAt: createdAt,
          attachmentPath: _attachment?.path,
        );
      } else {
        await Api.updateSupplierTransaction(
          transactionId: widget.transaction!['id'] as int,
          amount: amount,
          type: _type,
          note: _noteController.text.trim(),
          createdAt: createdAt,
          attachmentPath: _attachment?.path,
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.transaction != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Entry' : 'Add Entry')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _type == 'CREDIT' ? 'Type: You gave' : 'Type: You got',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Attach bill'),
                ),
                const SizedBox(width: 12),
                if (_attachment != null)
                  Expanded(
                    child: Text(
                      _attachment!.path.split('/').last,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Date: ${_date.toLocal().toString().split(' ').first}',
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _date = picked;
                      });
                    }
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _save,
              child: Text(isEdit ? 'Update' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
