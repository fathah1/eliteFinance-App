import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../routes.dart';
import 'entry_detail_screen.dart';

class SupplierTransactionsReportScreen extends StatefulWidget {
  const SupplierTransactionsReportScreen({super.key});

  @override
  State<SupplierTransactionsReportScreen> createState() =>
      _SupplierTransactionsReportScreenState();
}

class _TxRow {
  _TxRow({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.supplierPhone,
    required this.type,
    required this.amount,
    required this.createdAt,
    required this.note,
    required this.runningBalance,
    required this.raw,
  });

  final int id;
  final int supplierId;
  final String supplierName;
  final String supplierPhone;
  final String type;
  final double amount;
  final DateTime createdAt;
  final String note;
  final double runningBalance;
  final Map<String, dynamic> raw;
}

enum _DurationFilter {
  all('All'),
  thisMonth('This Month'),
  singleDay('Single Day'),
  lastWeek('Last Week'),
  lastMonth('Last Month'),
  dateRange('Date Range');

  const _DurationFilter(this.label);
  final String label;
}

class _SupplierTransactionsReportScreenState
    extends State<SupplierTransactionsReportScreen> {
  static const Color _brandBlue = Color(0xFF0B4F9E);

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _loading = true;
  bool _exporting = false;
  String _query = '';
  String _businessName = 'Business';
  _DurationFilter _duration = _DurationFilter.all;
  DateTime? _startDate;
  DateTime? _endDate;

  List<_TxRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    final businessName = prefs.getString('active_business_name');

    if (!mounted) return;
    setState(() {
      _businessName = (businessName == null || businessName.trim().isEmpty)
          ? 'Business'
          : businessName.trim();
      _loading = true;
    });

    if (businessId == null) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _loading = false;
      });
      return;
    }

    try {
      final suppliersRaw = await Api.getSuppliers(businessId: businessId);
      final txRaw =
          await Api.getAllSupplierTransactions(businessId: businessId);

      final supplierById = <int, Map<String, dynamic>>{};
      for (final c in suppliersRaw) {
        final m = Map<String, dynamic>.from(c as Map);
        supplierById[_asInt(m['id'])] = m;
      }

      final bySupplier = <int, List<Map<String, dynamic>>>{};
      for (final t in txRaw) {
        final m = Map<String, dynamic>.from(t as Map);
        final supplierId = _asInt(m['supplier_id'], fallback: -1);
        if (supplierId <= 0) continue;
        bySupplier.putIfAbsent(supplierId, () => []).add(m);
      }

      final runningByTxId = <int, double>{};
      for (final entry in bySupplier.entries) {
        final list = entry.value;
        list.sort((a, b) {
          final ad = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bd = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return ad.compareTo(bd);
        });
        var running = 0.0;
        for (final t in list) {
          final id = _asInt(t['id']);
          final amount = _asDouble(t['amount']);
          final type = (t['type'] ?? '').toString().toUpperCase();
          if (type == 'CREDIT') {
            running += amount;
          } else {
            running -= amount;
          }
          runningByTxId[id] = running;
        }
      }

      final rows = <_TxRow>[];
      for (final t in txRaw) {
        final m = Map<String, dynamic>.from(t as Map);
        final id = _asInt(m['id']);
        final supplierId = _asInt(m['supplier_id'], fallback: -1);
        if (id <= 0 || supplierId <= 0) continue;
        final created = DateTime.tryParse((m['created_at'] ?? '').toString()) ??
            DateTime.now();
        final supplier = supplierById[supplierId] ?? const {};
        rows.add(
          _TxRow(
            id: id,
            supplierId: supplierId,
            supplierName: (supplier['name'] ?? 'Supplier').toString(),
            supplierPhone: (supplier['phone'] ?? '').toString(),
            type: (m['type'] ?? '').toString().toUpperCase(),
            amount: _asDouble(m['amount']),
            createdAt: created,
            note: (m['note'] ?? '').toString(),
            runningBalance: runningByTxId[id] ?? 0,
            raw: m,
          ),
        );
      }

      rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load report: $e')),
      );
    }
  }

  bool _inRange(DateTime d) {
    if (_startDate != null && d.isBefore(_startDate!)) return false;
    if (_endDate != null &&
        d.isAfter(_endDate!
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1)))) {
      return false;
    }
    return true;
  }

  List<_TxRow> get _filtered {
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      if (!_inRange(r.createdAt)) return false;
      if (q.isEmpty) return true;
      return r.supplierName.toLowerCase().contains(q) ||
          r.supplierPhone.toLowerCase().contains(q) ||
          r.note.toLowerCase().contains(q) ||
          r.id.toString().contains(q) ||
          r.amount.toStringAsFixed(0).contains(q);
    }).toList();
  }

  double get _totalYouGave => _filtered
      .where((e) => e.type == 'CREDIT')
      .fold(0, (s, e) => s + e.amount);

  double get _totalYouGot =>
      _filtered.where((e) => e.type == 'DEBIT').fold(0, (s, e) => s + e.amount);

  double get _netBalance => _totalYouGave - _totalYouGot;

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
        if (_duration == _DurationFilter.singleDay) {
          _endDate = _startDate;
        }
      } else {
        _endDate = DateTime(picked.year, picked.month, picked.day);
      }
      _duration = _DurationFilter.dateRange;
    });
  }

  void _applyDuration(_DurationFilter filter) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;

    switch (filter) {
      case _DurationFilter.all:
        setState(() {
          _duration = filter;
          _startDate = null;
          _endDate = null;
        });
        return;
      case _DurationFilter.thisMonth:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      case _DurationFilter.singleDay:
        start = DateTime(now.year, now.month, now.day);
        end = start;
        break;
      case _DurationFilter.lastWeek:
        end = DateTime(now.year, now.month, now.day);
        start = end.subtract(const Duration(days: 6));
        break;
      case _DurationFilter.lastMonth:
        final firstThis = DateTime(now.year, now.month, 1);
        end = firstThis.subtract(const Duration(days: 1));
        start = DateTime(end.year, end.month, 1);
        break;
      case _DurationFilter.dateRange:
        start = _startDate ?? DateTime(now.year, now.month, now.day);
        end = _endDate ?? start;
        break;
    }
    setState(() {
      _duration = filter;
      _startDate = start;
      _endDate = end;
    });
  }

  Future<void> _openDurationPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select report duration',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              ..._DurationFilter.values.map((d) {
                return RadioListTile<_DurationFilter>(
                  contentPadding: EdgeInsets.zero,
                  value: d,
                  groupValue: _duration,
                  title: Text(
                    d.label,
                    style: const TextStyle(fontSize: 16),
                  ),
                  onChanged: (v) {
                    if (v == null) return;
                    Navigator.pop(context);
                    _applyDuration(v);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String _formatTopDate(DateTime? d, String fallback) {
    if (d == null) return fallback;
    return DateFormat('dd MMM yy').format(d).toUpperCase();
  }

  String _formatListDate(DateTime d) {
    return DateFormat('dd MMM yy • hh:mm a').format(d);
  }

  Future<void> _openEntry(_TxRow row) async {
    final attachment = (row.raw['attachment_path'] ?? '').toString();
    final attachmentUrl = attachment.isNotEmpty
        ? 'https://eliteposs.com/financeserver/public/storage/$attachment'
        : '';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntryDetailScreen(
          title: row.supplierName,
          entry: row.raw,
          runningBalance: row.runningBalance,
          attachmentUrl: attachmentUrl,
          onEdit: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              AppRoutes.onGenerateRoute(
                RouteSettings(
                  name: AppRoutes.addSupplierEntry,
                  arguments: {
                    'supplierId': row.supplierId,
                    'transaction': row.raw,
                  },
                ),
              ),
            ).then((_) => _load());
          },
          onDelete: () async {
            final nav = Navigator.of(context);
            await Api.deleteSupplierTransaction(row.id);
            if (!context.mounted) return;
            nav.pop();
            _load();
          },
        ),
      ),
    );
  }

  Future<void> _downloadPdf() async {
    if (_filtered.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final from = _startDate ?? _filtered.last.createdAt;
      final to = _endDate ?? _filtered.first.createdAt;

      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(20),
          build: (context) => [
            pw.Container(
              color: PdfColors.blue900,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(_businessName,
                      style: const pw.TextStyle(color: PdfColors.white)),
                  pw.Text('Account Statement',
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text('Account Statement',
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '(${DateFormat('dd MMM yyyy').format(from)} - ${DateFormat('dd MMM yyyy').format(to)})',
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300)),
              child: pw.Row(
                children: [
                  _pdfMetric('Total Debit(-)', _totalYouGave),
                  _pdfMetric('Total Credit(+)', _totalYouGot),
                  _pdfMetric('Net Balance', _netBalance.abs(),
                      red: _netBalance > 0),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('No. of Entries: ${_filtered.length} (${_duration.label})'),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FixedColumnWidth(55),
                1: const pw.FixedColumnWidth(90),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FixedColumnWidth(75),
                4: const pw.FixedColumnWidth(75),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _pdfCell('Date', bold: true),
                    _pdfCell('Name', bold: true),
                    _pdfCell('Details', bold: true),
                    _pdfCell('Debit(-)', bold: true),
                    _pdfCell('Credit(+)', bold: true),
                  ],
                ),
                ..._filtered.map((e) {
                  return pw.TableRow(
                    children: [
                      _pdfCell(DateFormat('dd MMM').format(e.createdAt)),
                      _pdfCell(e.supplierName),
                      _pdfCell(e.note),
                      _pdfCell(
                          e.type == 'CREDIT' ? e.amount.toStringAsFixed(2) : '',
                          bg: PdfColors.red50),
                      _pdfCell(
                          e.type == 'DEBIT' ? e.amount.toStringAsFixed(2) : '',
                          bg: PdfColors.green50),
                    ],
                  );
                }),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('Grand Total', bold: true),
                    _pdfCell('', bold: true),
                    _pdfCell('', bold: true),
                    _pdfCell(_totalYouGave.toStringAsFixed(2), bold: true),
                    _pdfCell(_totalYouGot.toStringAsFixed(2), bold: true),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Report Generated : ${DateFormat('hh:mm a | dd MMM yy').format(now)}',
              style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10),
            ),
          ],
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/supplier_transactions_${now.millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Supplier Transactions Report',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('PDF failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  pw.Widget _pdfMetric(String label, double value, {bool red = false}) {
    return pw.Expanded(
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 4),
            pw.Text(
              value.toStringAsFixed(2),
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: red ? PdfColors.red : PdfColors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfCell(String text, {bool bold = false, PdfColor? bg}) {
    return pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: 10,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchExpanded = _searchFocus.hasFocus;
    final rows = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        title: const Text('View Report'),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            color: _brandBlue,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _dateBox(
                        icon: Icons.calendar_month_outlined,
                        text: _formatTopDate(_startDate, 'START DATE'),
                        onTap: () => _pickDate(start: true),
                      ),
                    ),
                    const SizedBox(width: 1),
                    Expanded(
                      child: _dateBox(
                        icon: Icons.calendar_month_outlined,
                        text: _formatTopDate(_endDate, 'END DATE'),
                        onTap: () => _pickDate(start: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 14, right: 8),
                              child: Icon(Icons.search,
                                  color: _brandBlue, size: 30),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocus,
                                onChanged: (v) => setState(() => _query = v),
                                decoration: InputDecoration(
                                  hintText: searchExpanded
                                      ? 'Search Bill No., Name, amount'
                                      : 'Search Entries',
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            if (searchExpanded)
                              IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  _searchFocus.unfocus();
                                  setState(() => _query = '');
                                },
                                icon:
                                    const Icon(Icons.close, color: _brandBlue),
                              ),
                          ],
                        ),
                      ),
                      if (!searchExpanded) ...[
                        Container(width: 1, color: const Color(0xFFE2E6EC)),
                        InkWell(
                          onTap: _openDurationPicker,
                          child: Container(
                            width: 124,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEAF2FF),
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _duration.label.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _brandBlue,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: _brandBlue,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Net Balance',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'AED ${_netBalance.abs().toStringAsFixed(0)}',
                      style: TextStyle(
                        color: _netBalance > 0 ? Colors.red : Colors.green,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _summaryStat(
                        'TOTAL',
                        '${rows.length} Entries',
                        Colors.black87,
                      ),
                    ),
                    Expanded(
                      child: _summaryStat(
                        'YOU GAVE',
                        'AED ${_totalYouGave.toStringAsFixed(0)}',
                        Colors.red,
                      ),
                    ),
                    Expanded(
                      child: _summaryStat(
                        'YOU GOT',
                        'AED ${_totalYouGot.toStringAsFixed(0)}',
                        Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? const Center(child: Text('No entries found'))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          final gave = r.type == 'CREDIT';
                          return InkWell(
                            onTap: () => _openEntry(r),
                            child: Container(
                              color: Colors.white,
                              padding:
                                  const EdgeInsets.fromLTRB(12, 12, 12, 10),
                              margin: const EdgeInsets.only(bottom: 1),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.supplierName,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatListDate(r.createdAt),
                                          style: const TextStyle(
                                            color: Color(0xFF7A828F),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 90,
                                    color: gave
                                        ? const Color(0xFFFDEDEF)
                                        : Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Text(
                                      gave
                                          ? 'AED ${r.amount.toStringAsFixed(0)}'
                                          : '',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 90,
                                    color: gave
                                        ? Colors.white
                                        : const Color(0xFFE9F7EF),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Text(
                                      gave
                                          ? ''
                                          : 'AED ${r.amount.toStringAsFixed(0)}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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
                  onPressed: _exporting ? null : _downloadPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(_exporting ? 'DOWNLOADING...' : 'DOWNLOAD'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateBox({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.black54),
              const SizedBox(width: 10),
              Text(
                text,
                style: const TextStyle(
                  color: _brandBlue,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryStat(String title, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF7A828F),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> exportSupplierListPdfReport(BuildContext context) async {
  String businessName = 'Business';
  int? businessId;
  try {
    final prefs = await SharedPreferences.getInstance();
    businessId = prefs.getInt('active_business_server_id');
    businessName =
        (prefs.getString('active_business_name') ?? '').trim().isEmpty
            ? 'Business'
            : (prefs.getString('active_business_name') ?? 'Business');
  } catch (_) {}

  if (businessId == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No active business selected')),
    );
    return;
  }

  double asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  try {
    final suppliersRaw = await Api.getSuppliers(businessId: businessId);
    final txRaw = await Api.getAllSupplierTransactions(businessId: businessId);

    final bySupplier = <int, Map<String, dynamic>>{};
    for (final c in suppliersRaw) {
      final m = Map<String, dynamic>.from(c as Map);
      bySupplier[(m['id'] as num).toInt()] = m;
    }

    final totals = <int, double>{};
    final latestDate = <int, DateTime>{};
    for (final t in txRaw) {
      final m = Map<String, dynamic>.from(t as Map);
      final id = (m['supplier_id'] as num?)?.toInt();
      if (id == null) continue;
      final type = (m['type'] ?? '').toString().toUpperCase();
      final amount = asDouble(m['amount']);
      totals[id] = (totals[id] ?? 0) + (type == 'CREDIT' ? amount : -amount);
      final dt = DateTime.tryParse((m['created_at'] ?? '').toString());
      if (dt != null) {
        final prev = latestDate[id];
        if (prev == null || dt.isAfter(prev)) latestDate[id] = dt;
      }
    }

    final rows = <Map<String, dynamic>>[];
    var totalGet = 0.0;
    var totalGive = 0.0;
    for (final entry in bySupplier.entries) {
      final id = entry.key;
      final c = entry.value;
      final bal = totals[id] ?? 0;
      final get = bal > 0 ? bal : 0.0;
      final give = bal < 0 ? bal.abs() : 0.0;
      totalGet += get;
      totalGive += give;
      rows.add({
        'name': (c['name'] ?? '').toString(),
        'phone': (c['phone'] ?? '').toString(),
        'get': get,
        'give': give,
        'date': latestDate[id],
      });
    }

    rows.sort(
        (a, b) => ((b['get'] as double) - (a['get'] as double)).sign.toInt());

    final now = DateTime.now();
    final pdf = pw.Document();
    final net = (totalGet - totalGive).abs();

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(20),
        build: (_) => [
          pw.Container(
            color: PdfColors.blue900,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(businessName,
                    style: const pw.TextStyle(color: PdfColors.white)),
                pw.Text('Supplier List Report',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.Text(
              'Supplier List Report\n(As of Today - ${DateFormat('dd MMMM yyyy').format(now)})',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300)),
            child: pw.Row(
              children: [
                pw.Expanded(child: _pdfInfoMetric("You'll Get", totalGet)),
                pw.Expanded(child: _pdfInfoMetric("You'll Give", totalGive)),
                pw.Expanded(
                    child: _pdfInfoMetric('Net Balance', net,
                        red: totalGet > totalGive)),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('No. of Suppliers: ${rows.length} (All)'),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FixedColumnWidth(120),
              1: const pw.FixedColumnWidth(140),
              2: const pw.FixedColumnWidth(80),
              3: const pw.FixedColumnWidth(80),
              4: const pw.FixedColumnWidth(120),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _pdfC('Name', bold: true),
                  _pdfC('Details', bold: true),
                  _pdfC("You'll Get", bold: true),
                  _pdfC("You'll Give", bold: true),
                  _pdfC('Collection Date', bold: true),
                ],
              ),
              ...rows.map((r) => pw.TableRow(
                    children: [
                      _pdfC((r['name'] ?? '').toString()),
                      _pdfC((r['phone'] ?? '').toString()),
                      _pdfC(
                          (r['get'] as double) > 0
                              ? (r['get'] as double).toStringAsFixed(2)
                              : '',
                          bg: PdfColors.red50),
                      _pdfC(
                          (r['give'] as double) > 0
                              ? (r['give'] as double).toStringAsFixed(2)
                              : '',
                          bg: PdfColors.green50),
                      _pdfC(
                        r['date'] is DateTime
                            ? DateFormat('dd MMMM yyyy')
                                .format(r['date'] as DateTime)
                            : '',
                      ),
                    ],
                  )),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _pdfC('Grand Total', bold: true),
                  _pdfC('', bold: true),
                  _pdfC(totalGet.toStringAsFixed(2), bold: true),
                  _pdfC(totalGive.toStringAsFixed(2), bold: true),
                  _pdfC(''),
                ],
              )
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Report Generated : ${DateFormat('hh:mm a | dd MMM yy').format(now)}',
            style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10),
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/supplier_list_${now.millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'Supplier List Report');
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF failed: $e')),
    );
  }
}

pw.Widget _pdfInfoMetric(String title, double value, {bool red = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Text(
          value.toStringAsFixed(2),
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: red ? PdfColors.red : PdfColors.black,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _pdfC(String text, {bool bold = false, PdfColor? bg}) {
  return pw.Container(
    color: bg,
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontSize: 10,
      ),
    ),
  );
}
