import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';

enum _DurationFilter {
  thisYear('This year'),
  thisQuarter('This quarter'),
  thisMonth('This Month'),
  lastMonth('Last Month'),
  thisWeek('This week'),
  yesterday('Yesterday'),
  today('Today'),
  customDate('Custom Date');

  const _DurationFilter(this.label);
  final String label;
}

class VatReportScreen extends StatefulWidget {
  const VatReportScreen({super.key});

  @override
  State<VatReportScreen> createState() => _VatReportScreenState();
}

class _VatReportScreenState extends State<VatReportScreen> {
  static const Color _brandBlue = Color(0xFF0B5ECF);

  bool _loading = true;
  _DurationFilter _duration = _DurationFilter.today;
  DateTime? _startDate;
  DateTime? _endDate;

  double _salesVat = 0;
  double _purchaseVat = 0;
  double _expenseVat = 0;

  @override
  void initState() {
    super.initState();
    _applyDuration(_duration, refresh: false);
    _load();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  DateTime _toDate(dynamic value) {
    return DateTime.tryParse((value ?? '').toString()) ?? DateTime.now();
  }

  bool _isWithinRange(DateTime d) {
    if (_startDate == null || _endDate == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
    return !(day.isBefore(start) || day.isAfter(end));
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');

    if (businessId == null) {
      if (!mounted) return;
      setState(() {
        _salesVat = 0;
        _purchaseVat = 0;
        _expenseVat = 0;
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final sales = await Api.getSales(businessId: businessId);
      final purchases = await Api.getPurchases(businessId: businessId);
      final expenses = await Api.getExpenses(businessId: businessId);

      double salesVat = 0;
      for (final raw in sales) {
        final m = Map<String, dynamic>.from(raw as Map);
        if (_isWithinRange(_toDate(m['date']))) {
          salesVat += _toDouble(m['vat_amount']);
        }
      }

      double purchaseVat = 0;
      for (final raw in purchases) {
        final m = Map<String, dynamic>.from(raw as Map);
        if (_isWithinRange(_toDate(m['date']))) {
          purchaseVat += _toDouble(m['vat_amount']);
        }
      }

      double expenseVat = 0;
      for (final raw in expenses) {
        final m = Map<String, dynamic>.from(raw as Map);
        if (_isWithinRange(_toDate(m['date']))) {
          expenseVat += _toDouble(m['vat_amount']);
        }
      }

      if (!mounted) return;
      setState(() {
        _salesVat = salesVat;
        _purchaseVat = purchaseVat;
        _expenseVat = expenseVat;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _applyDuration(_DurationFilter value, {bool refresh = true}) {
    final now = DateTime.now();
    late DateTime start;
    late DateTime end;

    switch (value) {
      case _DurationFilter.thisYear:
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31);
        break;
      case _DurationFilter.thisQuarter:
        final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        start = DateTime(now.year, quarterStartMonth, 1);
        end = DateTime(now.year, quarterStartMonth + 3, 0);
        break;
      case _DurationFilter.thisMonth:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      case _DurationFilter.lastMonth:
        final firstThisMonth = DateTime(now.year, now.month, 1);
        end = firstThisMonth.subtract(const Duration(days: 1));
        start = DateTime(end.year, end.month, 1);
        break;
      case _DurationFilter.thisWeek:
        final weekday = now.weekday;
        start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weekday - 1));
        end = start.add(const Duration(days: 6));
        break;
      case _DurationFilter.yesterday:
        start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 1));
        end = start;
        break;
      case _DurationFilter.today:
        start = DateTime(now.year, now.month, now.day);
        end = start;
        break;
      case _DurationFilter.customDate:
        start = _startDate ?? DateTime(now.year, now.month, now.day);
        end = _endDate ?? start;
        break;
    }

    setState(() {
      _duration = value;
      _startDate = start;
      _endDate = end;
    });

    if (refresh) {
      _load();
    }
  }

  String _dateLabel(DateTime? d) {
    if (d == null) return '--';
    return DateFormat('dd MMM yy').format(d).toUpperCase();
  }

  String _money(double value) => 'AED ${value.toStringAsFixed(2)}';

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? (_startDate ?? DateTime.now()) : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    setState(() {
      _duration = _DurationFilter.customDate;
      if (start) {
        _startDate = picked;
        if (_endDate == null || _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
        if (_startDate == null || _startDate!.isAfter(picked)) {
          _startDate = picked;
        }
      }
    });
    _load();
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 23 / 2)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        title: const Text('VAT Report'),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            color: const Color(0xFFE7E9ED),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _openDurationSheet(),
                    child: _chip(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _duration.label,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down, color: _brandBlue),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(start: true),
                    child: _chip(
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_outlined, color: _brandBlue, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Start Date', style: TextStyle(fontSize: 12, color: Color(0xFF7A828F))),
                                Text(_dateLabel(_startDate), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(start: false),
                    child: _chip(
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_outlined, color: _brandBlue, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('End Date', style: TextStyle(fontSize: 12, color: Color(0xFF7A828F))),
                                Text(_dateLabel(_endDate), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD9DEE7)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _metric('Sales VAT', _money(_salesVat)),
                      const SizedBox(width: 10),
                      _metric('Purchase VAT', _money(_purchaseVat)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _metric('Expense VAT', _money(_expenseVat)),
                      const SizedBox(width: 10),
                      _metric('Net VAT', _money(_salesVat - (_purchaseVat + _expenseVat))),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  Future<void> _openDurationSheet() async {
    final selected = await showModalBottomSheet<_DurationFilter>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Select report duration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._DurationFilter.values.map((e) {
              final active = e == _duration;
              return ListTile(
                title: Text(
                  e.label,
                  style: TextStyle(
                    color: active ? _brandBlue : Colors.black87,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                trailing: Icon(
                  active ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: _brandBlue,
                ),
                onTap: () => Navigator.pop(context, e),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null) return;
    _applyDuration(selected);
  }
}
