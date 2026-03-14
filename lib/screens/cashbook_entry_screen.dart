import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';

class CashbookEntryScreen extends StatefulWidget {
  const CashbookEntryScreen({
    super.key,
    required this.businessId,
    required this.direction, // in|out
    required this.defaultPaymentMode, // cash|card
    required this.titlePrefix,
  });

  final int businessId;
  final String direction;
  final String defaultPaymentMode;
  final String titlePrefix;

  @override
  State<CashbookEntryScreen> createState() => _CashbookEntryScreenState();
}

class _CashbookEntryScreenState extends State<CashbookEntryScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String _paymentMode = 'cash';
  File? _photo;
  bool _saving = false;
  bool get _fixedPaymentMode => widget.defaultPaymentMode == 'cash' ||
      widget.defaultPaymentMode == 'card';

  bool get _isIn => widget.direction == 'in';
  Color get _accent => _isIn ? const Color(0xFF12965B) : const Color(0xFFDD123E);

  @override
  void initState() {
    super.initState();
    _paymentMode = widget.defaultPaymentMode == 'card' ? 'card' : 'cash';
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (picked == null) return;
    setState(() => _photo = File(picked.path));
  }

  Future<void> _save() async {
    final raw = _amount.text.trim();
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return;
    setState(() => _saving = true);
    try {
      await Api.createCashbookEntry(
        businessId: widget.businessId,
        direction: widget.direction,
        amount: value,
        paymentMode: _paymentMode == 'online' ? 'card' : _paymentMode,
        date: _date.toIso8601String().split('T').first,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        photoPath: _photo?.path,
      );
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
    final amountValue = _amount.text.trim().isEmpty ? '0' : _amount.text.trim();
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _accent,
        title: Text('${widget.titlePrefix} AED $amountValue'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              style: TextStyle(
                color: _accent,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                prefixText: 'AED ',
                prefixStyle: TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w700,
                ),
                hintText: 'Enter amount',
                hintStyle: TextStyle(color: _accent.withOpacity(0.6)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('Payment Mode',
                  style: TextStyle(color: Colors.black54)),
              const Spacer(),
              if (_fixedPaymentMode)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accent),
                  ),
                  child: Text(
                    _paymentMode == 'card' ? 'Bank' : 'Cash',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else ...[
                _modePill('Cash', 'cash'),
                const SizedBox(width: 8),
                _modePill('Online', 'online'),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _note,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter details (optional)',
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked == null) return;
                    setState(() => _date = picked);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: _accent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(_date),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Icon(Icons.arrow_drop_down, color: _accent),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: _pickImage,
                child: Container(
                  width: 76,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _photo == null
                      ? Icon(Icons.camera_alt, color: _accent)
                      : Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                _photo!,
                                width: 76,
                                height: 52,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: GestureDetector(
                                onTap: () => setState(() => _photo = null),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF12965B),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 54),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('SAVE',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }

  Widget _modePill(String label, String value) {
    final selected = _paymentMode == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMode = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _accent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
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
    return '${d.day} ${months[d.month - 1]} ${d.year % 100}';
  }
}
