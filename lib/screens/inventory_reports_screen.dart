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

enum InventoryReportType { stockSummary, lowStockSummary, profitLoss }

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

class _InventoryItemRow {
  const _InventoryItemRow({
    required this.id,
    required this.name,
    required this.currentStock,
    required this.lowStockAlert,
    required this.salePrice,
    required this.purchasePrice,
  });

  final int id;
  final String name;
  final double currentStock;
  final double lowStockAlert;
  final double salePrice;
  final double purchasePrice;
}

class _ProfitLossRow {
  const _ProfitLossRow({
    required this.name,
    required this.qty,
    required this.netSales,
    required this.netProfit,
  });

  final String name;
  final double qty;
  final double netSales;
  final double netProfit;
}

class InventoryReportsScreen extends StatefulWidget {
  const InventoryReportsScreen({
    super.key,
    required this.type,
  });

  final InventoryReportType type;

  @override
  State<InventoryReportsScreen> createState() => _InventoryReportsScreenState();
}

class _InventoryReportsScreenState extends State<InventoryReportsScreen> {
  static const Color _brandBlue = Color(0xFF0B5ECF);
  static const Color _bgGrey = Color(0xFFF1F3F6);
  static const Color _labelGrey = Color(0xFF767E8B);

  bool _loading = true;
  bool _downloading = false;
  String _businessName = 'Business';

  _DurationFilter _duration = _DurationFilter.thisMonth;
  DateTime? _startDate;
  DateTime? _endDate;

  final List<_InventoryItemRow> _items = [];
  final List<Map<String, dynamic>> _salesRaw = [];

  @override
  void initState() {
    super.initState();
    final defaultDuration = widget.type == InventoryReportType.profitLoss
        ? _DurationFilter.thisMonth
        : _DurationFilter.today;
    _applyDuration(defaultDuration, refresh: false);
    _load();
  }

  String get _title {
    switch (widget.type) {
      case InventoryReportType.stockSummary:
        return 'Stock Summary';
      case InventoryReportType.lowStockSummary:
        return 'Low Stock Summary Report';
      case InventoryReportType.profitLoss:
        return 'Profit & Loss Report';
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
        _items.clear();
        _salesRaw.clear();
        _loading = false;
      });
      return;
    }

    try {
      final itemRows =
          await Api.getItems(businessId: businessId, type: 'product');
      final parsedItems = itemRows.map((raw) {
        final m = Map<String, dynamic>.from(raw as Map);
        final lastPurchase = m['last_purchase_price'];
        final purchase = lastPurchase ?? m['purchase_price'] ?? '0';
        return _InventoryItemRow(
          id: _toInt(m['id']),
          name: (m['name'] ?? '').toString().trim().isEmpty
              ? 'Item'
              : (m['name'] ?? '').toString(),
          currentStock: _toDouble(m['current_stock']),
          lowStockAlert: _toDouble(m['low_stock_alert']),
          salePrice: _toDouble(m['sale_price']),
          purchasePrice: _toDouble(purchase),
        );
      }).toList();

      final salesRows = widget.type == InventoryReportType.profitLoss
          ? await Api.getSales(businessId: businessId)
          : <dynamic>[];

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(parsedItems);
        _salesRaw
          ..clear()
          ..addAll(
            salesRows.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );
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

  bool _withinRange(DateTime date) {
    if (_startDate == null || _endDate == null) return true;
    final from = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final to =
        DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
    return !date.isBefore(from) && !date.isAfter(to);
  }

  List<_ProfitLossRow> get _profitRows {
    final byItemName = <String, _InventoryItemRow>{
      for (final item in _items) item.name.trim().toLowerCase(): item,
    };
    final grouped = <String, Map<String, double>>{};

    for (final sale in _salesRaw) {
      final date = _saleDate(sale);
      if (date == null || !_withinRange(date)) continue;
      final lineItems = _saleLineItems(sale);
      for (final li in lineItems) {
        final name = _lineItemName(li);
        if (name.isEmpty) continue;
        final key = name.toLowerCase();
        final qty = _lineItemQty(li);
        final salesAmount = _lineItemSalesAmount(li, qty);
        final item = byItemName[key];
        final purchasePrice = item?.purchasePrice ?? 0;
        final cost = qty * purchasePrice;
        final profit = salesAmount - cost;

        final prev = grouped[key];
        if (prev == null) {
          grouped[key] = {
            'qty': qty,
            'sales': salesAmount,
            'profit': profit,
          };
        } else {
          prev['qty'] = (prev['qty'] ?? 0) + qty;
          prev['sales'] = (prev['sales'] ?? 0) + salesAmount;
          prev['profit'] = (prev['profit'] ?? 0) + profit;
        }
      }
    }

    final rows = grouped.entries
        .map(
          (e) => _ProfitLossRow(
            name: byItemName[e.key]?.name ?? e.key,
            qty: e.value['qty'] ?? 0,
            netSales: e.value['sales'] ?? 0,
            netProfit: e.value['profit'] ?? 0,
          ),
        )
        .toList();

    rows.sort((a, b) => b.netSales.compareTo(a.netSales));
    return rows;
  }

  DateTime? _saleDate(Map<String, dynamic> sale) {
    final candidates = [
      sale['date'],
      sale['created_at'],
      sale['invoice_date'],
      sale['bill_date'],
    ];
    for (final value in candidates) {
      final parsed = DateTime.tryParse((value ?? '').toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  List<Map<String, dynamic>> _saleLineItems(Map<String, dynamic> sale) {
    final candidates = [
      sale['line_items'],
      sale['items'],
      sale['products'],
    ];
    for (final value in candidates) {
      final items = _toListOfMap(value);
      if (items.isNotEmpty) return items;
    }
    return const [];
  }

  String _lineItemName(Map<String, dynamic> item) {
    final candidates = [
      item['name'],
      item['item_name'],
      item['title'],
      item['product_name'],
    ];
    for (final value in candidates) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  double _lineItemQty(Map<String, dynamic> item) {
    final candidates = [item['qty'], item['quantity']];
    for (final value in candidates) {
      final qty = _toDouble(value);
      if (qty > 0) return qty;
    }
    return 0;
  }

  double _lineItemSalesAmount(Map<String, dynamic> item, double qty) {
    final amountCandidates = [
      item['amount'],
      item['total_amount'],
      item['total'],
      item['line_total'],
    ];
    for (final value in amountCandidates) {
      final amount = _toDouble(value);
      if (amount != 0) return amount;
    }
    final unitPriceCandidates = [
      item['price'],
      item['sale_price'],
      item['rate']
    ];
    for (final value in unitPriceCandidates) {
      final price = _toDouble(value);
      if (price != 0) return price * qty;
    }
    return 0;
  }

  List<_InventoryItemRow> get _lowStockRows {
    final rows =
        _items.where((e) => e.currentStock <= e.lowStockAlert).toList();
    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  }

  int get _totalItems => _items.length;

  double get _totalStockCount =>
      _items.fold<double>(0, (sum, e) => sum + e.currentStock);

  int get _outOfStockItems => _lowStockRows.length;

  double get _profitTotalSales =>
      _profitRows.fold(0, (sum, e) => sum + e.netSales);

  double get _profitTotalProfit =>
      _profitRows.fold(0, (sum, e) => sum + e.netProfit);

  double get _profitTotalQty => _profitRows.fold(0, (sum, e) => sum + e.qty);

  String _money(double value) {
    final abs = value.abs();
    final isInteger = abs == abs.roundToDouble();
    return isInteger
        ? 'AED ${value.toStringAsFixed(0)}'
        : 'AED ${value.toStringAsFixed(2)}';
  }

  String _d(DateTime? date) {
    if (date == null) return '--';
    return DateFormat('dd MMM yy').format(date).toUpperCase();
  }

  String _todayLabel() {
    final now = DateTime.now();
    return 'Today (${DateFormat('dd MMM yy').format(now)})';
  }

  Future<void> _openDownloadSheet() async {
    if (_downloading) return;
    _ExportFormat format = _ExportFormat.pdf;

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
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _downloadReport(format: format);
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

  Future<void> _downloadReport({required _ExportFormat format}) async {
    setState(() => _downloading = true);
    try {
      final now = DateTime.now();
      final directory = await getApplicationDocumentsDirectory();
      late File file;
      if (format == _ExportFormat.pdf) {
        final bytes = await _buildPdfBytes();
        file = File(
            '${directory.path}/${_title.replaceAll(' ', '_')}_${now.millisecondsSinceEpoch}.pdf');
        await file.writeAsBytes(bytes);
      } else {
        final csv = _buildCsv();
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

  Future<List<int>> _buildPdfBytes() async {
    final pdf = pw.Document();

    if (widget.type == InventoryReportType.stockSummary) {
      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(18),
          build: (_) => [
            pw.Text(_businessName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text(_title,
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text(_todayLabel()),
            pw.SizedBox(height: 8),
            pw.Text('Total Items: $_totalItems'),
            pw.Text(
                'Total Stock Count: ${_totalStockCount.toStringAsFixed(1)}'),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                _pdfHead([
                  'Item',
                  'Current Stock',
                  'Current Sale Price',
                  'Stock Value (Sale)',
                  'Stock Value (Purchase)',
                ]),
                ..._items.map(
                  (row) => pw.TableRow(
                    children: [
                      _pdfCell(row.name),
                      _pdfCell(row.currentStock.toStringAsFixed(1)),
                      _pdfCell(_money(row.salePrice)),
                      _pdfCell(_money(row.currentStock * row.salePrice)),
                      _pdfCell(_money(row.currentStock * row.purchasePrice)),
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

    if (widget.type == InventoryReportType.lowStockSummary) {
      final rows = _lowStockRows;
      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(18),
          build: (_) => [
            pw.Text(_businessName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text(_title,
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text(_todayLabel()),
            pw.SizedBox(height: 8),
            pw.Text('Out of stock Items: $_outOfStockItems'),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                _pdfHead(['Item', 'Current Stock', 'Low Stock Level']),
                ...rows.map(
                  (row) => pw.TableRow(
                    children: [
                      _pdfCell(row.name),
                      _pdfCell(row.currentStock.toStringAsFixed(1)),
                      _pdfCell(row.lowStockAlert.toStringAsFixed(1)),
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

    final rows = _profitRows;
    final from = _startDate ?? DateTime.now();
    final to = _endDate ?? DateTime.now();
    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(18),
        build: (_) => [
          pw.Text(_businessName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(_title,
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(
            '${DateFormat('dd MMM yyyy').format(from)} - ${DateFormat('dd MMM yyyy').format(to)}',
          ),
          pw.SizedBox(height: 8),
          pw.Text('Total Sales: ${_money(_profitTotalSales)}'),
          pw.Text('Total Profit: ${_money(_profitTotalProfit)}'),
          pw.Text('Total Sales Qty: ${_profitTotalQty.toStringAsFixed(1)}'),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              _pdfHead([
                'Item',
                'Sales Qty',
                'Net Sales',
                'Net Profit',
              ]),
              ...rows.map(
                (row) => pw.TableRow(
                  children: [
                    _pdfCell(row.name),
                    _pdfCell(row.qty.toStringAsFixed(1)),
                    _pdfCell(_money(row.netSales)),
                    _pdfCell(_money(row.netProfit)),
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

  String _buildCsv() {
    if (widget.type == InventoryReportType.stockSummary) {
      final lines = <String>[
        'Stock Summary',
        _todayLabel(),
        'Total Items,$_totalItems',
        'Total Stock Count,${_totalStockCount.toStringAsFixed(1)}',
        '',
        'Item,Current Stock,Current Sale Price,Stock Value (on Sale Price),Stock Value (on Purchase Price)',
      ];
      for (final row in _items) {
        lines.add(
          '"${row.name.replaceAll('"', '""')}",${row.currentStock.toStringAsFixed(1)},${row.salePrice.toStringAsFixed(2)},${(row.currentStock * row.salePrice).toStringAsFixed(2)},${(row.currentStock * row.purchasePrice).toStringAsFixed(2)}',
        );
      }
      return lines.join('\n');
    }

    if (widget.type == InventoryReportType.lowStockSummary) {
      final rows = _lowStockRows;
      final lines = <String>[
        'Low Stock Summary Report',
        _todayLabel(),
        'Out of stock Items,$_outOfStockItems',
        '',
        'Item,Current Stock,Low Stock Level',
      ];
      for (final row in rows) {
        lines.add(
          '"${row.name.replaceAll('"', '""')}",${row.currentStock.toStringAsFixed(1)},${row.lowStockAlert.toStringAsFixed(1)}',
        );
      }
      return lines.join('\n');
    }

    final lines = <String>[
      'Profit & Loss Report',
      'From,${DateFormat('yyyy-MM-dd').format(_startDate ?? DateTime.now())}',
      'To,${DateFormat('yyyy-MM-dd').format(_endDate ?? DateTime.now())}',
      '',
      'Total Sales,${_profitTotalSales.toStringAsFixed(2)}',
      'Total Profit,${_profitTotalProfit.toStringAsFixed(2)}',
      'Total Sales Qty,${_profitTotalQty.toStringAsFixed(1)}',
      '',
      'Item,Sales qty in time period,Net Sales in time period,Net profit in time period',
    ];

    for (final row in _profitRows) {
      lines.add(
        '"${row.name.replaceAll('"', '""')}",${row.qty.toStringAsFixed(1)},${row.netSales.toStringAsFixed(2)},${row.netProfit.toStringAsFixed(2)}',
      );
    }
    return lines.join('\n');
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

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _labelGrey,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _topPnlFilters() {
    return Container(
      color: _bgGrey,
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

  Widget _todayTag() {
    return Container(
      color: _bgGrey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _todayLabel(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  Widget _stockTopSummary() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: _metric('Total Items', '$_totalItems'),
          ),
          Expanded(
            child: _metric(
                'Total Stock Count', _totalStockCount.toStringAsFixed(1)),
          ),
        ],
      ),
    );
  }

  Widget _lowStockTopSummary() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: _metric('Out of stock Items', '$_outOfStockItems'),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _pnlTopSummary() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: _metric('Total Sales', _money(_profitTotalSales)),
          ),
          Expanded(
            child: _metric('Total Profit', _money(_profitTotalProfit)),
          ),
          Expanded(
            child:
                _metric('Total Sales Qty', _profitTotalQty.toStringAsFixed(1)),
          ),
        ],
      ),
    );
  }

  Widget _stockBody() {
    if (_items.isEmpty) {
      return const Center(child: Text('No items found'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final row = _items[i];
        return Container(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                        'Current Stock', row.currentStock.toStringAsFixed(1)),
                  ),
                  Expanded(
                    child: _metric('Current Sale Price', _money(row.salePrice)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      'Stock Value (on Sale Price)',
                      _money(row.currentStock * row.salePrice),
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      'Stock Value (on Purchase Price)',
                      _money(row.currentStock * row.purchasePrice),
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

  Widget _lowStockBody() {
    final rows = _lowStockRows;
    if (rows.isEmpty) {
      return const Center(child: Text('No low stock items'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final row = rows[i];
        return Container(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                        'Current Stock', row.currentStock.toStringAsFixed(1)),
                  ),
                  Expanded(
                    child: _metric('Low Stock level',
                        row.lowStockAlert.toStringAsFixed(1)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pnlBody() {
    final rows = _profitRows;
    if (rows.isEmpty) {
      return const Center(child: Text('No sales found in selected duration'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final row = rows[i];
        return Container(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      'Sales qty in time period',
                      row.qty.toStringAsFixed(1),
                    ),
                  ),
                  Expanded(
                    child: _metric(
                      'Net Sales in time period',
                      _money(row.netSales),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      'Net profit in time period',
                      _money(row.netProfit),
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGrey,
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (widget.type == InventoryReportType.profitLoss) _topPnlFilters(),
          if (widget.type != InventoryReportType.profitLoss) _todayTag(),
          if (widget.type == InventoryReportType.stockSummary)
            _stockTopSummary(),
          if (widget.type == InventoryReportType.lowStockSummary)
            _lowStockTopSummary(),
          if (widget.type == InventoryReportType.profitLoss) _pnlTopSummary(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : widget.type == InventoryReportType.stockSummary
                    ? _stockBody()
                    : widget.type == InventoryReportType.lowStockSummary
                        ? _lowStockBody()
                        : _pnlBody(),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: _bgGrey,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _downloading ? null : _openDownloadSheet,
                  icon: const Icon(Icons.download_outlined),
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
}
