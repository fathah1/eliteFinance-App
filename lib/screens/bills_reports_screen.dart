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

enum BillReportType { sales, purchase, cashbook }

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

enum _DownloadFormat { pdf, excel }

class _BillDocRow {
  const _BillDocRow({
    required this.number,
    required this.date,
    required this.partyName,
    required this.partyPhone,
    required this.amount,
    required this.paidAmount,
    required this.balance,
    required this.paymentMode,
    required this.statusLabel,
    required this.items,
  });

  final int number;
  final DateTime date;
  final String partyName;
  final String partyPhone;
  final double amount;
  final double paidAmount;
  final double balance;
  final String paymentMode;
  final String statusLabel;
  final List<Map<String, dynamic>> items;
}

class _CashEntry {
  const _CashEntry({
    required this.date,
    required this.amount,
    required this.direction,
    required this.label,
  });

  final DateTime date;
  final double amount;
  final String direction; // in|out
  final String label;
}

class _CashDayRow {
  const _CashDayRow({
    required this.date,
    required this.dailyBalance,
    required this.totalBalance,
  });

  final DateTime date;
  final double dailyBalance;
  final double totalBalance;
}

class BillsReportScreen extends StatefulWidget {
  const BillsReportScreen({
    super.key,
    required this.type,
  });

  final BillReportType type;

  @override
  State<BillsReportScreen> createState() => _BillsReportScreenState();
}

class _BillsReportScreenState extends State<BillsReportScreen> {
  static const Color _brandBlue = Color(0xFF0B4F9E);
  static const Color _green = Color(0xFF12965B);
  static const Color _red = Color(0xFFC6284D);

  bool _loading = true;
  bool _downloading = false;
  String _businessName = 'Business';
  _DurationFilter _duration = _DurationFilter.thisMonth;
  DateTime? _startDate;
  DateTime? _endDate;

  final List<_BillDocRow> _sales = [];
  final List<_BillDocRow> _purchases = [];
  final List<_CashEntry> _cashEntries = [];

  @override
  void initState() {
    super.initState();
    _applyDuration(_duration, refresh: false);
    _load();
  }

  String get _title {
    switch (widget.type) {
      case BillReportType.sales:
        return 'Sales Report';
      case BillReportType.purchase:
        return 'Purchase Report';
      case BillReportType.cashbook:
        return 'Cashbook Report';
    }
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
        _sales.clear();
        _purchases.clear();
        _cashEntries.clear();
        _loading = false;
      });
      return;
    }

    try {
      final salesRaw = await Api.getSales(businessId: businessId);
      final purchaseRaw = await Api.getPurchases(businessId: businessId);
      final expensesRaw = await Api.getExpenses(businessId: businessId);

      final sales = <_BillDocRow>[];
      final purchases = <_BillDocRow>[];
      final cashEntries = <_CashEntry>[];

      for (final raw in salesRaw) {
        final m = Map<String, dynamic>.from(raw as Map);
        final total = _toDouble(m['total_amount']);
        final received = _toDouble(m['received_amount']);
        final balance = _toDouble(m['balance_due']) > 0
            ? _toDouble(m['balance_due'])
            : (total - received).clamp(0, total).toDouble();
        final paymentMode = (m['payment_mode'] ?? 'unpaid').toString();
        final unpaid = paymentMode == 'unpaid' && balance > 0;
        final date = _toDate(m['date']);
        final number = _toInt(m['bill_number']);
        final partyName = ((m['party_name'] ?? '').toString().trim().isEmpty)
            ? 'Sale Bill'
            : (m['party_name'] ?? '').toString();

        sales.add(
          _BillDocRow(
            number: number,
            date: date,
            partyName: partyName,
            partyPhone: (m['party_phone'] ?? '').toString(),
            amount: total,
            paidAmount: received,
            balance: balance,
            paymentMode: paymentMode,
            statusLabel: unpaid ? 'Unpaid' : 'Fully Paid',
            items: _toListOfMap(m['line_items']),
          ),
        );

        if (received > 0) {
          cashEntries.add(
            _CashEntry(
              date: date,
              amount: received,
              direction: 'in',
              label: 'Payment In #$number',
            ),
          );
        }
      }

      for (final raw in purchaseRaw) {
        final m = Map<String, dynamic>.from(raw as Map);
        final total = _toDouble(m['total_amount']);
        final paid = _toDouble(m['paid_amount']);
        final balance = _toDouble(m['balance_due']) > 0
            ? _toDouble(m['balance_due'])
            : (total - paid).clamp(0, total).toDouble();
        final paymentMode = (m['payment_mode'] ?? 'unpaid').toString();
        final unpaid = paymentMode == 'unpaid' && balance > 0;
        final date = _toDate(m['date']);
        final number = _toInt(m['purchase_number']);
        final partyName = ((m['party_name'] ?? '').toString().trim().isEmpty)
            ? 'Purchase'
            : (m['party_name'] ?? '').toString();

        purchases.add(
          _BillDocRow(
            number: number,
            date: date,
            partyName: partyName,
            partyPhone: (m['party_phone'] ?? '').toString(),
            amount: total,
            paidAmount: paid,
            balance: balance,
            paymentMode: paymentMode,
            statusLabel: unpaid ? 'Unpaid' : 'Fully Paid',
            items: _toListOfMap(m['line_items']),
          ),
        );

        if (paid > 0) {
          cashEntries.add(
            _CashEntry(
              date: date,
              amount: paid,
              direction: 'out',
              label: 'Payment Out #$number',
            ),
          );
        }
      }

      for (final raw in expensesRaw) {
        final m = Map<String, dynamic>.from(raw as Map);
        final number = _toInt(m['expense_number']);
        cashEntries.add(
          _CashEntry(
            date: _toDate(m['date']),
            amount: _toDouble(m['amount']),
            direction: 'out',
            label: 'Expense #$number',
          ),
        );
      }

      sales.sort((a, b) => b.date.compareTo(a.date));
      purchases.sort((a, b) => b.date.compareTo(a.date));
      cashEntries.sort((a, b) => b.date.compareTo(a.date));

      if (!mounted) return;
      setState(() {
        _sales
          ..clear()
          ..addAll(sales);
        _purchases
          ..clear()
          ..addAll(purchases);
        _cashEntries
          ..clear()
          ..addAll(cashEntries);
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

  List<_BillDocRow> get _saleRows =>
      _sales.where((row) => _withinRange(row.date)).toList();

  List<_BillDocRow> get _purchaseRows =>
      _purchases.where((row) => _withinRange(row.date)).toList();

  List<_CashDayRow> get _cashDayRows {
    final now = DateTime.now();
    final from = _startDate ?? DateTime(now.year, now.month, 1);
    final to = _endDate ?? DateTime(now.year, now.month + 1, 0);
    if (to.isBefore(from)) return const [];

    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    final map = <String, double>{};

    for (final e in _cashEntries) {
      final key = DateFormat('yyyy-MM-dd').format(e.date);
      final sign = e.direction == 'in' ? 1.0 : -1.0;
      map[key] = (map[key] ?? 0) + (sign * e.amount);
    }

    var balanceBefore = 0.0;
    for (final e in _cashEntries) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      if (d.isBefore(fromDay)) {
        balanceBefore += (e.direction == 'in' ? 1.0 : -1.0) * e.amount;
      }
    }

    final ascending = <_CashDayRow>[];
    var running = balanceBefore;
    var cursor = fromDay;
    while (!cursor.isAfter(toDay)) {
      final key = DateFormat('yyyy-MM-dd').format(cursor);
      final daily = map[key] ?? 0;
      running += daily;
      ascending.add(
        _CashDayRow(date: cursor, dailyBalance: daily, totalBalance: running),
      );
      cursor = cursor.add(const Duration(days: 1));
    }
    return ascending.reversed.toList();
  }

  double get _netSale => _saleRows.fold(0, (sum, e) => sum + e.amount);
  double get _netPurchase => _purchaseRows.fold(0, (sum, e) => sum + e.amount);
  double get _unpaidSale => _saleRows.fold(0, (sum, e) => sum + e.balance);
  double get _unpaidPurchase =>
      _purchaseRows.fold(0, (sum, e) => sum + e.balance);

  String _money(double value) => 'AED ${value.toStringAsFixed(0)}';

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
        final weekday = now.weekday; // Mon=1
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

  String _day(DateTime date) => DateFormat('dd MMM').format(date);

  Widget _topDurationAndDate() {
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
                          style: const TextStyle(fontSize: 14))),
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
                          style: const TextStyle(fontSize: 14))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topCashbookControls() {
    return Container(
      color: _brandBlue,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _box(
                  onTap: () => _pickDate(start: true),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined,
                          color: _brandBlue, size: 18),
                      const SizedBox(width: 10),
                      Text(_d(_startDate),
                          style: const TextStyle(
                            color: _brandBlue,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: _box(
                  onTap: () => _pickDate(start: false),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined,
                          color: _brandBlue, size: 18),
                      const SizedBox(width: 10),
                      Text(_d(_endDate),
                          style: const TextStyle(
                            color: _brandBlue,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _box(
            onTap: _openDurationSheet,
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select report duration',
                    style: TextStyle(color: Color(0xFF6C7583), fontSize: 14),
                  ),
                ),
                Container(
                  color: const Color(0xFFEAF2FF),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      Text(
                        _duration.label.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _brandBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.keyboard_arrow_down, color: _brandBlue),
                    ],
                  ),
                ),
              ],
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

  Future<void> _openDownloadSheet() async {
    if (_downloading) return;
    _DownloadFormat format = _DownloadFormat.pdf;
    bool includeItems = true;
    bool includeStatus = true;
    bool includePhone = true;

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
                  RadioListTile<_DownloadFormat>(
                    contentPadding: EdgeInsets.zero,
                    value: _DownloadFormat.pdf,
                    groupValue: format,
                    onChanged: (v) => setModalState(() => format = v!),
                    title: const Text('Download PDF'),
                    secondary:
                        const Icon(Icons.picture_as_pdf, color: Colors.red),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  if (format == _DownloadFormat.excel ||
                      format == _DownloadFormat.pdf) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        FilterChip(
                          selected: includeItems,
                          label: const Text('Item Details'),
                          onSelected: (_) =>
                              setModalState(() => includeItems = !includeItems),
                        ),
                        FilterChip(
                          selected: includeStatus,
                          label: const Text('Payment Status'),
                          onSelected: (_) => setModalState(
                              () => includeStatus = !includeStatus),
                        ),
                        FilterChip(
                          selected: includePhone,
                          label: const Text('Party Phone No.'),
                          onSelected: (_) =>
                              setModalState(() => includePhone = !includePhone),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  RadioListTile<_DownloadFormat>(
                    contentPadding: EdgeInsets.zero,
                    value: _DownloadFormat.excel,
                    groupValue: format,
                    onChanged: (v) => setModalState(() => format = v!),
                    title: const Text('Download Excel'),
                    secondary:
                        const Icon(Icons.table_chart, color: Colors.green),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _downloadReport(
                          format: format,
                          includeItems: includeItems,
                          includeStatus: includeStatus,
                          includePhone: includePhone,
                        );
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

  Future<void> _downloadReport({
    required _DownloadFormat format,
    required bool includeItems,
    required bool includeStatus,
    required bool includePhone,
  }) async {
    setState(() => _downloading = true);
    try {
      final now = DateTime.now();
      final directory = await getApplicationDocumentsDirectory();
      late File file;
      if (format == _DownloadFormat.pdf) {
        final bytes = await _buildPdfBytes(
          includeItems: includeItems,
          includeStatus: includeStatus,
          includePhone: includePhone,
        );
        file = File(
            '${directory.path}/${_title.replaceAll(' ', '_')}_${now.millisecondsSinceEpoch}.pdf');
        await file.writeAsBytes(bytes);
      } else {
        final csv = _buildCsv(
          includeItems: includeItems,
          includeStatus: includeStatus,
          includePhone: includePhone,
        );
        file = File(
            '${directory.path}/${_title.replaceAll(' ', '_')}_${now.millisecondsSinceEpoch}.csv');
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
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<List<int>> _buildPdfBytes({
    required bool includeItems,
    required bool includeStatus,
    required bool includePhone,
  }) async {
    final pdf = pw.Document();
    final from = _startDate ?? DateTime.now();
    final to = _endDate ?? DateTime.now();

    if (widget.type == BillReportType.cashbook) {
      final rows = _cashDayRows;
      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(18),
          build: (_) => [
            _pdfHeader(from: from, to: to),
            pw.SizedBox(height: 12),
            pw.Text('Cashbook Report',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                _pdfTableHead(['Date', 'Daily Balance', 'Total Balance']),
                ...rows.map(
                  (r) => pw.TableRow(
                    children: [
                      _pdfCell(DateFormat('dd MMM yy').format(r.date)),
                      _pdfCell(r.dailyBalance.toStringAsFixed(2)),
                      _pdfCell(r.totalBalance.toStringAsFixed(2)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      return pdf.save();
    }

    final rows =
        widget.type == BillReportType.sales ? _saleRows : _purchaseRows;
    final total = rows.fold<double>(0, (sum, r) => sum + r.amount);

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(18),
        build: (_) => [
          _pdfHeader(from: from, to: to),
          pw.SizedBox(height: 12),
          pw.Text(
            '${widget.type == BillReportType.sales ? 'Sales' : 'Purchase'} Report',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('No. of entries: ${rows.length}'),
          pw.Text(
            'Total ${widget.type == BillReportType.sales ? 'Sale' : 'Purchase'} Amount: AED ${total.toStringAsFixed(0)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              _pdfTableHead([
                'S.No',
                'Date',
                'Inv No.',
                'Name',
                if (includePhone) 'Phone',
                if (includeStatus) 'Status',
                'Total',
              ]),
              ...rows.asMap().entries.map((entry) {
                final i = entry.key;
                final row = entry.value;
                return pw.TableRow(
                  children: [
                    _pdfCell('${i + 1}'),
                    _pdfCell(DateFormat('dd MMM yy').format(row.date)),
                    _pdfCell('${row.number}'),
                    _pdfCell(row.partyName),
                    if (includePhone) _pdfCell(row.partyPhone),
                    if (includeStatus) _pdfCell(row.statusLabel),
                    _pdfCell('AED ${row.amount.toStringAsFixed(0)}'),
                  ],
                );
              }),
            ],
          ),
          if (includeItems) ...[
            pw.SizedBox(height: 10),
            pw.Text('Item Details',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            ...rows.map((row) {
              if (row.items.isEmpty) return pw.SizedBox();
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${widget.type == BillReportType.sales ? 'Sale Bill' : 'Purchase'} #${row.number}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                    children: [
                      _pdfTableHead(['Item', 'Qty', 'Price/Unit', 'Amount']),
                      ...row.items.map((item) => pw.TableRow(children: [
                            _pdfCell((item['name'] ?? '').toString()),
                            _pdfCell(_toDouble(item['qty']).toStringAsFixed(1)),
                            _pdfCell(
                                'AED ${_toDouble(item['price']).toStringAsFixed(0)}'),
                            _pdfCell(
                                'AED ${_toDouble(item['amount']).toStringAsFixed(0)}'),
                          ])),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                ],
              );
            }),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  pw.Widget _pdfHeader({required DateTime from, required DateTime to}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_businessName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.Text(
          '${DateFormat('dd MMM yyyy').format(from)} to ${DateFormat('dd MMM yyyy').format(to)}',
        ),
      ],
    );
  }

  pw.TableRow _pdfTableHead(List<String> cells) {
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

  String _buildCsv({
    required bool includeItems,
    required bool includeStatus,
    required bool includePhone,
  }) {
    if (widget.type == BillReportType.cashbook) {
      final rows = _cashDayRows;
      final lines = <String>[
        'Date,Daily Balance,Total Balance',
        ...rows.map((r) =>
            '${DateFormat('yyyy-MM-dd').format(r.date)},${r.dailyBalance.toStringAsFixed(2)},${r.totalBalance.toStringAsFixed(2)}'),
      ];
      return lines.join('\n');
    }

    final rows =
        widget.type == BillReportType.sales ? _saleRows : _purchaseRows;
    final headers = <String>[
      'S.No',
      'Date',
      'Invoice No',
      'Name',
      if (includePhone) 'Phone',
      if (includeStatus) 'Status',
      'Total',
      if (includeItems) 'Items',
    ];
    final lines = <String>[headers.join(',')];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final items = includeItems
          ? row.items
              .map((it) =>
                  '${(it['name'] ?? '').toString()} x ${_toDouble(it['qty']).toStringAsFixed(1)}')
              .join(' | ')
          : '';
      final values = <String>[
        '${i + 1}',
        DateFormat('yyyy-MM-dd').format(row.date),
        '${row.number}',
        '"${row.partyName.replaceAll('"', '""')}"',
        if (includePhone) '"${row.partyPhone.replaceAll('"', '""')}"',
        if (includeStatus) row.statusLabel,
        row.amount.toStringAsFixed(2),
        if (includeItems) '"${items.replaceAll('"', '""')}"',
      ];
      lines.add(values.join(','));
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.type == BillReportType.sales;
    final purchase = widget.type == BillReportType.purchase;
    final cashbook = widget.type == BillReportType.cashbook;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (sale || purchase) _topDurationAndDate(),
          if (cashbook) _topCashbookControls(),
          if (sale || purchase) _summaryHeader(sale: sale),
          if (cashbook) _cashbookHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _listBody(),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: const Color(0xFFF1F3F6),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _downloading ? null : _openDownloadSheet,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(_downloading ? 'DOWNLOADING...' : 'DOWNLOAD'),
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

  Widget _summaryHeader({required bool sale}) {
    final rows = sale ? _saleRows : _purchaseRows;
    final net = sale ? _netSale : _netPurchase;
    final unpaid = sale ? _unpaidSale : _unpaidPurchase;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: _metric('TRANSACTIONS', '${rows.length}', Colors.black87),
          ),
          Expanded(
            child: _metric(
              sale ? 'NET SALE' : 'NET PURCHASE',
              _money(net),
              _green,
            ),
          ),
          Expanded(
            child: _metric(
              'UNPAID BALANCE',
              _money(unpaid),
              _green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cashbookHeader() {
    return Container(
      color: const Color(0xFFF1F3F6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: const Row(
        children: [
          Expanded(
            child: Text(
              'DATE',
              style: TextStyle(
                color: Color(0xFF656D79),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'DAILY BALANCE',
              style: TextStyle(
                color: Color(0xFF656D79),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'TOTAL BALANCE',
              style: TextStyle(
                color: Color(0xFF656D79),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6A7380),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _listBody() {
    if (widget.type == BillReportType.cashbook) {
      final rows = _cashDayRows;
      if (rows.isEmpty) return const Center(child: Text('No cashbook rows'));
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final row = rows[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD8DEE8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _day(row.date),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    _money(row.dailyBalance.abs()),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        _money(row.totalBalance.abs()),
                        style: TextStyle(
                          color: row.totalBalance < 0 ? _red : _green,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right, color: _brandBlue),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    final rows =
        widget.type == BillReportType.sales ? _saleRows : _purchaseRows;
    if (rows.isEmpty) return const Center(child: Text('No data found'));
    final icon = widget.type == BillReportType.sales
        ? Icons.note_alt_outlined
        : Icons.shopping_cart_outlined;
    final rowLabel =
        widget.type == BillReportType.sales ? 'Sale Bill' : 'Purchase';

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final row = rows[i];
        final unpaid = row.statusLabel.toLowerCase().contains('unpaid');
        return Container(
          margin: const EdgeInsets.only(bottom: 1),
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFF2F8FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _brandBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.partyName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F4F4),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: const Color(0xFFD8D8D8)),
                          ),
                          child: Text(
                            '$rowLabel #${row.number}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF7C7C7C),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('dd MMM yy').format(row.date),
                          style: const TextStyle(
                            color: Color(0xFF7A828F),
                            fontSize: 13,
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
                    _money(row.amount),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.statusLabel,
                    style: TextStyle(
                      color: unpaid ? _red : _green,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
