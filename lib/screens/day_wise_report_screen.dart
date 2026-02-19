import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';

enum DayWiseReportType { sales, purchase }

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

enum _ExportFormat { pdf, excel }

class _LineItem {
  const _LineItem({
    required this.name,
    required this.qty,
    required this.amount,
  });

  final String name;
  final double qty;
  final double amount;
}

class _DocEntry {
  const _DocEntry({
    required this.number,
    required this.date,
    required this.total,
    required this.settled,
    required this.unpaid,
    required this.items,
  });

  final int number;
  final DateTime date;
  final double total;
  final double settled;
  final double unpaid;
  final List<_LineItem> items;
}

class _ItemSummary {
  const _ItemSummary({
    required this.name,
    required this.totalQty,
    required this.totalDocs,
    required this.totalValue,
  });

  final String name;
  final double totalQty;
  final int totalDocs;
  final double totalValue;
}

class _DaySummary {
  const _DaySummary({
    required this.date,
    required this.entries,
  });

  final DateTime date;
  final List<_DocEntry> entries;

  int get totalCount => entries.length;

  double get totalValue => entries.fold(0, (sum, e) => sum + e.total);

  double get settledAmount => entries.fold(0, (sum, e) => sum + e.settled);

  double get unpaidAmount => entries.fold(0, (sum, e) => sum + e.unpaid);

  List<_ItemSummary> get itemSummaries {
    final map = <String, Map<String, dynamic>>{};
    for (final e in entries) {
      for (final item in e.items) {
        final key = item.name.trim().isEmpty ? 'Item' : item.name.trim();
        final prev = map[key];
        if (prev == null) {
          map[key] = {
            'qty': item.qty,
            'docs': 1,
            'value': item.amount,
          };
        } else {
          prev['qty'] = (prev['qty'] as double) + item.qty;
          prev['docs'] = (prev['docs'] as int) + 1;
          prev['value'] = (prev['value'] as double) + item.amount;
        }
      }
    }

    final rows = map.entries
        .map(
          (e) => _ItemSummary(
            name: e.key,
            totalQty: e.value['qty'] as double,
            totalDocs: e.value['docs'] as int,
            totalValue: e.value['value'] as double,
          ),
        )
        .toList();

    rows.sort((a, b) => b.totalValue.compareTo(a.totalValue));
    return rows;
  }
}

class DayWiseReportScreen extends StatefulWidget {
  const DayWiseReportScreen({
    super.key,
    required this.type,
  });

  final DayWiseReportType type;

  @override
  State<DayWiseReportScreen> createState() => _DayWiseReportScreenState();
}

class _DayWiseReportScreenState extends State<DayWiseReportScreen> {
  static const Color _brandBlue = Color(0xFF0B5ECF);
  static const Color _green = Color(0xFF12965B);
  static const Color _red = Color(0xFFC6284D);

  bool _loading = true;
  bool _exporting = false;
  String _businessName = 'Business';

  _DurationFilter _duration = _DurationFilter.today;
  DateTime? _startDate;
  DateTime? _endDate;

  final List<_DocEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _applyDuration(_duration, refresh: false);
    _load();
  }

  String get _title {
    return widget.type == DayWiseReportType.sales
        ? 'Sales Day-wise Report'
        : 'Purchase Day-wise Report';
  }

  String get _actionLabel {
    return widget.type == DayWiseReportType.sales ? 'Sales' : 'Purchases';
  }

  String get _countMetricLabel {
    return widget.type == DayWiseReportType.sales
        ? 'Total Sales Made'
        : 'Total Purchases Made';
  }

  String get _valueMetricLabel {
    return widget.type == DayWiseReportType.sales
        ? 'Total Sales Value'
        : 'Total Purchases Value';
  }

  String get _settledMetricLabel {
    return widget.type == DayWiseReportType.sales
        ? 'Received Amount'
        : 'Paid Amount';
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  DateTime _toDate(dynamic value) {
    return DateTime.tryParse((value ?? '').toString()) ?? DateTime.now();
  }

  List<Map<String, dynamic>> _toListOfMap(dynamic value) {
    if (value is List) {
      return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    final businessName = prefs.getString('active_business_name')?.trim();

    if (!mounted) return;
    setState(() {
      _businessName = (businessName == null || businessName.isEmpty)
          ? 'Business'
          : businessName;
      _loading = true;
    });

    if (businessId == null) {
      if (!mounted) return;
      setState(() {
        _entries.clear();
        _loading = false;
      });
      return;
    }

    try {
      final rawRows = widget.type == DayWiseReportType.sales
          ? await Api.getSales(businessId: businessId)
          : await Api.getPurchases(businessId: businessId);

      final parsed = <_DocEntry>[];

      for (final raw in rawRows) {
        final m = Map<String, dynamic>.from(raw as Map);
        final total = _toDouble(m['total_amount']);
        final settled = widget.type == DayWiseReportType.sales
            ? _toDouble(m['received_amount'])
            : _toDouble(m['paid_amount']);
        final unpaid = _toDouble(m['balance_due']) > 0
            ? _toDouble(m['balance_due'])
            : (total - settled).clamp(0, total).toDouble();
        final items = _toListOfMap(m['line_items'])
            .map(
              (item) => _LineItem(
                name: (item['name'] ?? '').toString(),
                qty: _toDouble(item['qty']),
                amount: _toDouble(item['amount']),
              ),
            )
            .toList();

        parsed.add(
          _DocEntry(
            number: _toInt(
              widget.type == DayWiseReportType.sales
                  ? m['bill_number']
                  : m['purchase_number'],
            ),
            date: _toDate(m['date']),
            total: total,
            settled: settled,
            unpaid: unpaid,
            items: items,
          ),
        );
      }

      parsed.sort((a, b) => b.date.compareTo(a.date));

      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(parsed);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load report: $e')),
      );
    }
  }

  bool _withinRange(DateTime date) {
    if (_startDate == null || _endDate == null) return true;
    final from = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final to =
        DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
    return !date.isBefore(from) && !date.isAfter(to);
  }

  List<_DocEntry> get _filteredEntries {
    return _entries.where((row) => _withinRange(row.date)).toList();
  }

  List<_DaySummary> get _dayRows {
    final grouped = <String, List<_DocEntry>>{};
    for (final row in _filteredEntries) {
      final day = DateTime(row.date.year, row.date.month, row.date.day);
      final key = DateFormat('yyyy-MM-dd').format(day);
      (grouped[key] ??= <_DocEntry>[]).add(row);
    }

    final rows = grouped.entries.map((entry) {
      final d = DateTime.parse(entry.key);
      final docs = List<_DocEntry>.from(entry.value)
        ..sort((a, b) => b.date.compareTo(a.date));
      return _DaySummary(date: d, entries: docs);
    }).toList();

    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  int get _totalCount => _filteredEntries.length;

  double get _totalValue => _filteredEntries.fold(0, (sum, e) => sum + e.total);

  double get _totalSettled =>
      _filteredEntries.fold(0, (sum, e) => sum + e.settled);

  double get _totalUnpaid =>
      _filteredEntries.fold(0, (sum, e) => sum + e.unpaid);

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

    if (refresh) {}
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial =
        start ? (_startDate ?? now) : (_endDate ?? _startDate ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    setState(() {
      if (start) {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = DateTime(picked.year, picked.month, picked.day);
      }
      _duration = _DurationFilter.customDate;
    });
  }

  Future<void> _openDurationSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.75;
        return SizedBox(
          height: maxHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select report duration',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: _DurationFilter.values
                        .map(
                          (option) => RadioListTile<_DurationFilter>(
                            contentPadding: EdgeInsets.zero,
                            value: option,
                            groupValue: _duration,
                            title: Text(option.label),
                            onChanged: (value) {
                              if (value == null) return;
                              Navigator.pop(context);
                              _applyDuration(value);
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _d(DateTime? date) {
    if (date == null) return '--';
    return DateFormat('dd MMM yy').format(date).toUpperCase();
  }

  String _dateBadge(DateTime date) {
    return DateFormat('dd\nMMM').format(date);
  }

  void _openDayDetail(_DaySummary day) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DayWiseReportDetailScreen(
          type: widget.type,
          day: day,
          money: _money,
        ),
      ),
    );
  }

  String _money(double value) {
    final abs = value.abs();
    final isInteger = abs == abs.roundToDouble();
    return isInteger
        ? '₹${value.toStringAsFixed(0)}'
        : '₹${value.toStringAsFixed(2)}';
  }

  Future<void> _openExportSheet() async {
    if (_exporting || _dayRows.isEmpty) return;

    _ExportFormat format = _ExportFormat.pdf;
    bool includeItems = true;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<_ExportFormat>(
                    contentPadding: EdgeInsets.zero,
                    value: _ExportFormat.pdf,
                    groupValue: format,
                    onChanged: (v) => setModalState(() => format = v!),
                    title: const Text('Download PDF'),
                    secondary:
                        const Icon(Icons.picture_as_pdf, color: Colors.red),
                  ),
                  const Divider(height: 1),
                  RadioListTile<_ExportFormat>(
                    contentPadding: EdgeInsets.zero,
                    value: _ExportFormat.excel,
                    groupValue: format,
                    onChanged: (v) => setModalState(() => format = v!),
                    title: const Text('Download Excel'),
                    secondary:
                        const Icon(Icons.table_chart, color: Colors.green),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeItems,
                    onChanged: (v) =>
                        setModalState(() => includeItems = v ?? true),
                    title: const Text('Item Details'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _export(format: format, includeItems: includeItems);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brandBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: const Text('DOWNLOAD'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _export({
    required _ExportFormat format,
    required bool includeItems,
  }) async {
    setState(() => _exporting = true);
    try {
      final now = DateTime.now();
      final directory = await getApplicationDocumentsDirectory();
      final cleanTitle = _title.replaceAll(' ', '_');
      late File file;

      if (format == _ExportFormat.pdf) {
        final bytes = await _buildPdfBytes(includeItems: includeItems);
        file = File(
            '${directory.path}/${cleanTitle}_${now.millisecondsSinceEpoch}.pdf');
        await file.writeAsBytes(bytes);
      } else {
        final csv = _buildCsv(includeItems: includeItems);
        file = File(
            '${directory.path}/${cleanTitle}_${now.millisecondsSinceEpoch}.csv');
        await file.writeAsString(csv);
      }

      await Share.shareXFiles([XFile(file.path)], text: _title);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report Download Successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<List<int>> _buildPdfBytes({required bool includeItems}) async {
    final pdf = pw.Document();
    final dayRows = _dayRows;
    final from = _startDate ?? DateTime.now();
    final to = _endDate ?? DateTime.now();
    final generatedAt = DateFormat('h:mm a | d MMM yy').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(18),
        build: (_) => [
          pw.Text(
            _businessName,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '$_actionLabel Day-wise Report',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
          pw.Text(
            '(${DateFormat('dd MMM yyyy').format(from)} - ${DateFormat('dd MMM yyyy').format(to)})',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              _pdfHead([
                _countMetricLabel,
                _valueMetricLabel,
                _settledMetricLabel,
                'Unpaid Amount',
              ]),
              pw.TableRow(
                children: [
                  _pdfCell('$_totalCount'),
                  _pdfCell(_money(_totalValue)),
                  _pdfCell(_money(_totalSettled)),
                  _pdfCell(_money(_totalUnpaid)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          ...dayRows.expand((day) {
            final widgets = <pw.Widget>[
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  _pdfHead([
                    'Date',
                    _countMetricLabel,
                    _valueMetricLabel,
                    _settledMetricLabel,
                    'Unpaid Amount',
                  ]),
                  pw.TableRow(
                    children: [
                      _pdfCell(DateFormat('dd MMM yy').format(day.date)),
                      _pdfCell('${day.totalCount}'),
                      _pdfCell(_money(day.totalValue)),
                      _pdfCell(_money(day.settledAmount)),
                      _pdfCell(_money(day.unpaidAmount)),
                    ],
                  ),
                ],
              ),
            ];

            if (includeItems) {
              final itemRows = day.itemSummaries;
              if (itemRows.isNotEmpty) {
                widgets.add(
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                    children: [
                      _pdfHead([
                        'Item',
                        'Total Qty',
                        widget.type == DayWiseReportType.sales
                            ? 'Total Sales'
                            : 'Total Purchases',
                        'Total Value',
                      ]),
                      ...itemRows.map(
                        (item) => pw.TableRow(
                          children: [
                            _pdfCell(item.name),
                            _pdfCell(item.totalQty.toStringAsFixed(1)),
                            _pdfCell('${item.totalDocs}'),
                            _pdfCell(_money(item.totalValue)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
            }

            widgets.add(pw.SizedBox(height: 8));
            return widgets;
          }),
          pw.SizedBox(height: 12),
          pw.Text(
            'Report Generated : $generatedAt',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.TableRow _pdfHead(List<String> cells) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: cells.map((cell) => _pdfCell(cell, bold: true)).toList(),
    );
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  String _buildCsv({required bool includeItems}) {
    final lines = <String>[
      '$_actionLabel Day-wise Report',
      'From,${DateFormat('yyyy-MM-dd').format(_startDate ?? DateTime.now())}',
      'To,${DateFormat('yyyy-MM-dd').format(_endDate ?? DateTime.now())}',
      '',
      '$_countMetricLabel,$_valueMetricLabel,$_settledMetricLabel,Unpaid Amount',
      '$_totalCount,${_totalValue.toStringAsFixed(2)},${_totalSettled.toStringAsFixed(2)},${_totalUnpaid.toStringAsFixed(2)}',
      '',
    ];

    for (final day in _dayRows) {
      lines.add('Date,${DateFormat('yyyy-MM-dd').format(day.date)}');
      lines.add(
        '$_countMetricLabel,$_valueMetricLabel,$_settledMetricLabel,Unpaid Amount',
      );
      lines.add(
        '${day.totalCount},${day.totalValue.toStringAsFixed(2)},${day.settledAmount.toStringAsFixed(2)},${day.unpaidAmount.toStringAsFixed(2)}',
      );

      if (includeItems) {
        lines.add(
            'Item,Total Qty,${widget.type == DayWiseReportType.sales ? 'Total Sales' : 'Total Purchases'},Total Value');
        for (final item in day.itemSummaries) {
          lines.add(
            '"${item.name.replaceAll('"', '""')}",${item.totalQty.toStringAsFixed(1)},${item.totalDocs},${item.totalValue.toStringAsFixed(2)}',
          );
        }
      }
      lines.add('');
    }

    return lines.join('\n');
  }

  Widget _topFilters() {
    return Container(
      color: const Color(0xFFF1F3F6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: _box(
              onTap: _openDurationSheet,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_duration.label, style: const TextStyle(fontSize: 14)),
                  const Icon(Icons.keyboard_arrow_down, color: _brandBlue),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: _box(
              onTap: () => _pickDate(start: true),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined,
                      color: _brandBlue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_d(_startDate),
                        style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: _box(
              onTap: () => _pickDate(start: false),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined,
                      color: _brandBlue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_d(_endDate),
                        style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box({required Widget child, VoidCallback? onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }

  Widget _metricCell(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF707887),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildDayCard(_DaySummary day) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openDayDetail(day),
        child: Container(
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          color: Colors.white,
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF9DC4F2)),
                ),
                alignment: Alignment.center,
                child: Text(
                  _dateBadge(day.date),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _brandBlue,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _metricCell(
                            _countMetricLabel,
                            '${day.totalCount}',
                            Colors.black,
                          ),
                        ),
                        Expanded(
                          child: _metricCell(
                            _valueMetricLabel,
                            _money(day.totalValue),
                            Colors.black,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _metricCell(
                            _settledMetricLabel,
                            _money(day.settledAmount),
                            _green,
                          ),
                        ),
                        Expanded(
                          child: _metricCell(
                            'Unpaid Amount',
                            _money(day.unpaidAmount),
                            _red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Color(0xFFBAC1CB)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 88,
              color: Color(0xFF9BA3AF),
            ),
            SizedBox(height: 16),
            Text(
              'No transactions available to generate reports',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Color(0xFF222A35)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _dayRows;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _topFilters(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: rows.length,
                        itemBuilder: (_, i) => _buildDayCard(rows[i]),
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: const Color(0xFFF1F3F6),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      (_exporting || rows.isEmpty) ? null : _openExportSheet,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(_exporting ? 'EXPORTING...' : 'EXPORT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayWiseReportDetailScreen extends StatelessWidget {
  const _DayWiseReportDetailScreen({
    required this.type,
    required this.day,
    required this.money,
  });

  final DayWiseReportType type;
  final _DaySummary day;
  final String Function(double) money;

  static const Color _brandBlue = Color(0xFF0B5ECF);
  static const Color _green = Color(0xFF12965B);
  static const Color _red = Color(0xFFC6284D);

  String get _countMetricLabel {
    return type == DayWiseReportType.sales
        ? 'Total Sales Made'
        : 'Total Purchases Made';
  }

  String get _valueMetricLabel {
    return type == DayWiseReportType.sales
        ? 'Total Sales Value'
        : 'Total Purchase Value';
  }

  String get _settledMetricLabel {
    return type == DayWiseReportType.sales ? 'Received Amount' : 'Paid Amount';
  }

  String get _docsMetricLabel {
    return type == DayWiseReportType.sales ? 'Total Sales' : 'Total Purchase';
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF707887),
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemRows = day.itemSummaries;
    final title = '${DateFormat('dd MMM yy').format(day.date)} Report';
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _metric(
                        _countMetricLabel,
                        '${day.totalCount}',
                        Colors.black,
                      ),
                    ),
                    Expanded(
                      child: _metric(
                        _valueMetricLabel,
                        money(day.totalValue),
                        Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _metric(
                        _settledMetricLabel,
                        money(day.settledAmount),
                        _green,
                      ),
                    ),
                    Expanded(
                      child: _metric(
                        'Unpaid Amount',
                        money(day.unpaidAmount),
                        _red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            color: const Color(0xFFE7E9ED),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: const Text(
              'Item Summary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          if (itemRows.isEmpty)
            Container(
              color: Colors.white,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: const Text(
                'No item details',
                style: TextStyle(color: Color(0xFF707887)),
              ),
            )
          else
            ...itemRows.map(
              (item) => Container(
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 1),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _metric(
                            'Total Qty',
                            item.totalQty.toStringAsFixed(1),
                            Colors.black,
                          ),
                        ),
                        Expanded(
                          child: _metric(
                            _docsMetricLabel,
                            '${item.totalDocs}',
                            Colors.black,
                          ),
                        ),
                        Expanded(
                          child: _metric(
                            'Total Value',
                            money(item.totalValue),
                            Colors.black,
                          ),
                        ),
                      ],
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
