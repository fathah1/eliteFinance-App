import 'package:flutter/material.dart';

import '../api.dart';
import 'add_expense_screen.dart';

class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({super.key, required this.expenseId});

  final int expenseId;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _expense;

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
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final row = await Api.getExpense(id: widget.expenseId);
      if (!mounted) return;
      setState(() {
        _expense = row;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not load expense: $e')));
    }
  }

  Future<void> _edit() async {
    if (_expense == null) return;
    final draft = await Navigator.push<ExpenseDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          expenseNumber: _toInt(_expense!['expense_number'], fallback: 1),
          expense: _expense,
        ),
      ),
    );
    if (draft == null || draft.saved != true) return;
    await _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Expense'),
        content: const Text('This expense will be deleted permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await Api.deleteExpense(id: widget.expenseId);
      if (!mounted) return;
      Navigator.pop(context, ExpenseDraft(saved: true, deleted: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Text('Expense #${widget.expenseId}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _expense == null
              ? const Center(child: Text('Expense not found'))
              : _buildContent(),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: OutlinedButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC6284D),
              side: const BorderSide(color: Color(0xFFC6284D)),
              minimumSize: const Size(double.infinity, 56),
            ),
            label: const Text(
              'DELETE EXPENSE',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    const brandBlue = Color(0xFF0B4F9E);
    final amount = _toDouble(_expense!['amount']);
    final date = DateTime.tryParse((_expense!['date'] ?? '').toString()) ??
        DateTime.now();
    final items = (_expense!['items'] as List?) ?? const [];

    return ListView(
      children: [
        const SizedBox(height: 16),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFFFCEAF0),
                      child: Icon(Icons.money_off_csred_outlined,
                          color: Color(0xFFC6284D)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Expense',
                            style: TextStyle(
                              fontSize: 34 / 2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_formatTime(date)} ${date.day.toString().padLeft(2, '0')} ${_month(date.month)} ${date.year}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'AED ${amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Color(0xFFC6284D),
                        fontSize: 34 / 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Items',
                    style: TextStyle(color: Colors.black54, fontSize: 18),
                  ),
                ),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No items'),
                  ),
                )
              else
                ...items.map((e) {
                  final m = Map<String, dynamic>.from(e as Map);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Row(
                      children: [
                        Expanded(child: Text((m['name'] ?? '').toString())),
                        Text(
                            'AED ${_toDouble(m['line_total']).toStringAsFixed(0)}'),
                      ],
                    ),
                  );
                }),
              const Divider(height: 1),
              TextButton(
                onPressed: _edit,
                child: const Text(
                  'EDIT EXPENSE',
                  style: TextStyle(
                    color: brandBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 34 / 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final hour24 = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:$minute $suffix';
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
