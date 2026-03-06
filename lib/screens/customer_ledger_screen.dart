import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../notifications.dart';
import '../routes.dart';
import 'entry_detail_screen.dart';

class CustomerLedgerScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerLedgerScreen({super.key, required this.customer});

  @override
  State<CustomerLedgerScreen> createState() => _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends State<CustomerLedgerScreen> {
  List<Map<String, dynamic>> _transactions = [];
  double _balance = 0;
  bool _loading = true;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _loadReminder();
    _load();
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d $m $y • $h:$min';
  }

  Future<void> _loadReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'customer_due_${widget.customer['id']}';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    final dt = DateTime.tryParse(raw);
    if (!mounted) return;
    setState(() {
      _dueDate = dt;
    });
  }

  Future<void> _saveReminder(DateTime? date) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'customer_due_${widget.customer['id']}';
    final notifyId = 100000 + (widget.customer['id'] as int);
    if (date == null) {
      await prefs.remove(key);
      await NotificationService.cancel(notifyId);
      return;
    }
    await prefs.setString(key, date.toIso8601String());
    await NotificationService.schedulePaymentReminder(
      id: notifyId,
      title: 'Payment due',
      body:
          'Reminder to collect from ${widget.customer['name'] ?? 'customer'}.',
      date: date,
    );
  }

  String _dueLabel() {
    if (_dueDate == null) return 'Set collection reminder';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day);
    if (due == today) return 'Payment is due Today';
    if (due.isBefore(today)) return 'Payment is overdue';
    final fmt = DateFormat('dd MMM yy');
    return 'Payment is due ${fmt.format(due)}';
  }

  String _overdueDateLabel() {
    if (_dueDate == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day);
    if (due.isBefore(today)) {
      return DateFormat('dd MMM yy').format(due);
    }
    return '';
  }

  void _openReminderSheet() {
    final name = (widget.customer['name'] ?? '').toString();
    DateTime? selected = _dueDate;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            final today = DateTime.now();
            final nextWeek = today.add(const Duration(days: 7));
            final nextMonth = DateTime(today.year, today.month + 1, today.day);

            String selectedKey() {
              if (selected == null) return '';
              final d =
                  DateTime(selected!.year, selected!.month, selected!.day);
              final nw = DateTime(nextWeek.year, nextWeek.month, nextWeek.day);
              final nm =
                  DateTime(nextMonth.year, nextMonth.month, nextMonth.day);
              if (d == nw) return 'next_week';
              if (d == nm) return 'next_month';
              return 'calendar';
            }

            Widget buildOption(String key, String label, DateTime date) {
              final isSelected = selected != null &&
                  DateTime(selected!.year, selected!.month, selected!.day) ==
                      DateTime(date.year, date.month, date.day);
              return ListTile(
                leading: Radio<String>(
                  value: key,
                  groupValue: selectedKey(),
                  onChanged: (_) async {
                    selected = date;
                    setStateSheet(() {});
                    if (mounted) {
                      setState(() => _dueDate = date);
                    }
                    await _saveReminder(date);
                    Navigator.pop(context);
                  },
                ),
                title: Text(label),
                onTap: () async {
                  selected = date;
                  setStateSheet(() {});
                  if (mounted) {
                    setState(() => _dueDate = date);
                  }
                  await _saveReminder(date);
                  Navigator.pop(context);
                },
              );
            }

            final calendarLabel = selected == null
                ? 'Select date'
                : DateFormat('dd MMM yy').format(selected!);

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Set due date for $name',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'app will remind customer on selected date',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                  const Divider(height: 24),
                  buildOption('next_week', 'Next Week', nextWeek),
                  buildOption('next_month', 'Next Month', nextMonth),
                  ListTile(
                    leading: Radio<String>(
                      value: 'calendar',
                      groupValue: selectedKey(),
                      onChanged: (_) async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selected ?? today,
                          firstDate:
                              DateTime(today.year, today.month, today.day),
                          lastDate: today.add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          selected = picked;
                          setStateSheet(() {});
                          if (mounted) {
                            setState(() => _dueDate = picked);
                          }
                          await _saveReminder(picked);
                          Navigator.pop(context);
                        }
                      },
                    ),
                    title: const Text('Calendar'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, size: 18),
                        const SizedBox(width: 8),
                        Text(calendarLabel),
                      ],
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selected ?? today,
                        firstDate: DateTime(today.year, today.month, today.day),
                        lastDate: today.add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) {
                        selected = picked;
                        setStateSheet(() {});
                        if (mounted) {
                          setState(() => _dueDate = picked);
                        }
                        await _saveReminder(picked);
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const Divider(height: 24),
                  TextButton(
                    onPressed: () async {
                      if (mounted) {
                        setState(() => _dueDate = null);
                      }
                      await _saveReminder(null);
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: Colors.red),
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final tx = await Api.getCustomerTransactions(
        customerId: widget.customer['id'] as int,
      );

      final opening = 0.0;
      final list = tx
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      list.sort((a, b) {
        final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime(1970);
        final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime(1970);
        return da.compareTo(db);
      });

      double running = opening;
      for (final t in list) {
        final type = (t['type'] ?? '').toString();
        final amount = _asDouble(t['amount']);
        if (type == 'CREDIT') {
          running += amount;
        } else {
          running -= amount;
        }
        t['running_balance'] = running;
      }

      final credit = list
          .where((t) => t['type'] == 'CREDIT')
          .fold<double>(0, (sum, t) => sum + _asDouble(t['amount']));
      final debit = list
          .where((t) => t['type'] == 'DEBIT')
          .fold<double>(0, (sum, t) => sum + _asDouble(t['amount']));
      final balance = opening + credit - debit;

      if (!mounted) return;
      setState(() {
        _transactions = list.reversed.toList();
        _balance = balance;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _transactions = [];
        _loading = false;
      });
    }
  }

  Color _balanceColor(double balance) {
    if (balance > 0) return Colors.red;
    if (balance < 0) return Colors.green;
    return Colors.grey;
  }

  String _paymentMessage(String name, String? phone, double amount) {
    final safePhone = (phone ?? '').trim();
    final amountLabel = amount.abs().toStringAsFixed(0);
    final contact = safePhone.isEmpty ? name : '$name ($safePhone)';
    return '$contact has requested a payment of AED $amountLabel.';
  }

  String? _partyAvatarUrl() {
    return Api.resolveMediaUrl(
      widget.customer['photo_url'] ??
          widget.customer['photoPath'] ??
          widget.customer['photo_path'] ??
          widget.customer['photo'] ??
          widget.customer['image_url'] ??
          widget.customer['avatar_url'],
    );
  }

  ImageProvider? _partyAvatarProvider() {
    final url = _partyAvatarUrl();
    if (url == null) return null;
    return NetworkImage(url);
  }

  Future<void> _showAvatarPreview() async {
    final url = _partyAvatarUrl();
    if (url == null) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 1,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(
    String name,
    String? phone,
    double amount,
  ) {
    final avatar = _partyAvatarProvider();
    final time = DateFormat('hh:mm a dd MMM yyyy').format(DateTime.now());
    final amountLabel = amount.abs().toStringAsFixed(0);
    const appName = 'app';
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFE9EEF9),
              backgroundImage: avatar,
              child: avatar == null
                  ? Text(
                      name.trim().isEmpty
                          ? 'C'
                          : name.trim().toUpperCase().substring(0, 1),
                      style: const TextStyle(
                        color: Color(0xFF0B4F9E),
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            Text(
              name.isEmpty ? 'Customer' : name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (phone != null && phone.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  phone,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              'Requested at $time',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Text(
              'AED $amountLabel',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            const Text(
              appName,
              style: TextStyle(
                color: Color(0xFFB0182E),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareOnWhatsApp(double amount) async {
    final user = await Api.getUser();
    final userName = (user?['username'] ?? 'User').toString();
    final userPhone =
        user?['phone'] == null ? null : (user?['phone'] ?? '').toString();
    final controller = ScreenshotController();
    final mediaQuery = MediaQueryData(
      size: const Size(360, 640),
      devicePixelRatio: 2.0,
      textScaler: TextScaler.linear(1),
    );
    final widget = MediaQuery(
      data: mediaQuery,
      child: Directionality(
        textDirection: ui.TextDirection.ltr,
        child: Container(
          color: Colors.white,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: _buildRequestCard(userName, userPhone, amount),
        ),
      ),
    );
    final Uint8List imageBytes = await controller.captureFromWidget(
      widget,
      pixelRatio: 2.0,
    );
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/payment_request_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(imageBytes);
    final message = _paymentMessage(userName, userPhone, amount);
    await Share.shareXFiles([XFile(file.path)], text: message);
  }

  Future<void> _sendSms(double amount) async {
    final user = await Api.getUser();
    final userName = (user?['username'] ?? 'User').toString();
    final userPhone =
        user?['phone'] == null ? '' : (user?['phone'] ?? '').toString();
    final number = userPhone.trim();
    if (number.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number found.')),
      );
      return;
    }
    final message =
        Uri.encodeComponent(_paymentMessage(userName, userPhone, amount));
    final uri = Uri.parse('sms:$number?body=$message');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _reportPeriodLabel(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty)
      return DateFormat('dd MMM yyyy').format(DateTime.now());
    final dates = entries
        .map((t) => DateTime.tryParse((t['created_at'] ?? '').toString()))
        .whereType<DateTime>()
        .toList();
    if (dates.isEmpty) return DateFormat('dd MMM yyyy').format(DateTime.now());
    dates.sort((a, b) => a.compareTo(b));
    final start = DateFormat('dd MMM yyyy').format(dates.first);
    final end = DateFormat('dd MMM yyyy').format(dates.last);
    return '$start - $end';
  }

  List<Map<String, dynamic>> _allEntriesAsc() {
    final entriesAsc = _transactions.reversed.toList();
    return entriesAsc;
  }

  List<Map<String, dynamic>> _filterEntriesByDateRange({
    required DateTime start,
    required DateTime end,
  }) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    return _allEntriesAsc().where((t) {
      final dt = DateTime.tryParse((t['created_at'] ?? '').toString());
      if (dt == null) return false;
      return !dt.isBefore(s) && !dt.isAfter(e);
    }).toList();
  }

  Future<List<Map<String, dynamic>>?> _pickReportEntries() async {
    final option = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            children: [
              const ListTile(
                title: Text(
                  'Select report duration',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                        title: const Text('All'),
                        onTap: () => Navigator.pop(ctx, 'all')),
                    ListTile(
                        title: const Text('This Month'),
                        onTap: () => Navigator.pop(ctx, 'this_month')),
                    ListTile(
                        title: const Text('Last Month'),
                        onTap: () => Navigator.pop(ctx, 'last_month')),
                    ListTile(
                        title: const Text('This Week'),
                        onTap: () => Navigator.pop(ctx, 'this_week')),
                    ListTile(
                        title: const Text('Today'),
                        onTap: () => Navigator.pop(ctx, 'today')),
                    ListTile(
                        title: const Text('Yesterday'),
                        onTap: () => Navigator.pop(ctx, 'yesterday')),
                    ListTile(
                        title: const Text('Single Day'),
                        onTap: () => Navigator.pop(ctx, 'single_day')),
                    ListTile(
                        title: const Text('Date Range'),
                        onTap: () => Navigator.pop(ctx, 'date_range')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (option == null) return null;

    final now = DateTime.now();
    if (option == 'all') return _allEntriesAsc();
    if (option == 'today') {
      return _filterEntriesByDateRange(start: now, end: now);
    }
    if (option == 'yesterday') {
      final y = now.subtract(const Duration(days: 1));
      return _filterEntriesByDateRange(start: y, end: y);
    }
    if (option == 'this_week') {
      final start = now.subtract(Duration(days: now.weekday - 1));
      return _filterEntriesByDateRange(start: start, end: now);
    }
    if (option == 'this_month') {
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0);
      return _filterEntriesByDateRange(start: start, end: end);
    }
    if (option == 'last_month') {
      final start = DateTime(now.year, now.month - 1, 1);
      final end = DateTime(now.year, now.month, 0);
      return _filterEntriesByDateRange(start: start, end: end);
    }
    if (option == 'single_day') {
      final day = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (day == null) return null;
      return _filterEntriesByDateRange(start: day, end: day);
    }
    if (option == 'date_range') {
      final start = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (start == null) return null;
      final end = await showDatePicker(
        context: context,
        initialDate: start,
        firstDate: start,
        lastDate: DateTime(2100),
      );
      if (end == null) return null;
      return _filterEntriesByDateRange(start: start, end: end);
    }
    return _allEntriesAsc();
  }

  String _sanitizePhoneForWhatsApp(String raw) {
    final keepPlus = raw.trim().startsWith('+');
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return keepPlus ? '+$digits' : digits;
  }

  Future<File> _buildCustomerReportPdf({
    required List<Map<String, dynamic>> entriesAsc,
  }) async {
    final customerName = (widget.customer['name'] ?? 'Customer').toString();
    final customerPhone = (widget.customer['phone'] ?? '').toString();
    final now = DateTime.now();
    final totalCredit = entriesAsc
        .where((t) => (t['type'] ?? '').toString().toUpperCase() == 'CREDIT')
        .fold<double>(0, (sum, t) => sum + _asDouble(t['amount']));
    final totalDebit = entriesAsc
        .where((t) => (t['type'] ?? '').toString().toUpperCase() == 'DEBIT')
        .fold<double>(0, (sum, t) => sum + _asDouble(t['amount']));
    final net = totalCredit - totalDebit;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          margin: pw.EdgeInsets.all(24),
        ),
        build: (context) => [
          pw.Text(
            'Customer Report',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Customer: $customerName'),
          if (customerPhone.trim().isNotEmpty) pw.Text('Phone: $customerPhone'),
          pw.Text('Period: ${_reportPeriodLabel(entriesAsc)}'),
          pw.Text(
              'Generated: ${DateFormat('dd MMM yyyy hh:mm a').format(now)}'),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('You gave: AED ${totalCredit.toStringAsFixed(0)}'),
                pw.Text('You got: AED ${totalDebit.toStringAsFixed(0)}'),
                pw.Text(
                  'Net: AED ${net.abs().toStringAsFixed(0)}',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: net >= 0 ? PdfColors.red700 : PdfColors.green700,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(1.3),
              1: const pw.FlexColumnWidth(1.7),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
            },
            headers: const ['Date', 'Note', 'Type', 'Amount', 'Balance'],
            data: entriesAsc.map((t) {
              final type = (t['type'] ?? '').toString().toUpperCase();
              final date =
                  DateTime.tryParse((t['created_at'] ?? '').toString());
              final dateLabel = date == null
                  ? '-'
                  : DateFormat('dd MMM yy, hh:mm a').format(date);
              return [
                dateLabel,
                (t['note'] ?? '').toString(),
                type == 'CREDIT' ? 'You gave' : 'You got',
                'AED ${_asDouble(t['amount']).toStringAsFixed(0)}',
                'AED ${_asDouble(t['running_balance']).toStringAsFixed(0)}',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/customer_report_${widget.customer['id']}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await pdf.save(), flush: true);
    return file;
  }

  Future<void> _downloadCustomerReportPdf() async {
    try {
      final entriesAsc = await _pickReportEntries();
      if (entriesAsc == null) return;
      if (entriesAsc.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No entries found for selected duration')),
        );
        return;
      }
      final file = await _buildCustomerReportPdf(entriesAsc: entriesAsc);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Report saved'),
          content: Text(
            'Saved to:\n${file.path}\n\n'
            'To open it:\n'
            '1. Open Files/My Files app\n'
            '2. Go to Android/data/com.example.app/files\n'
            '3. Open the PDF file',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await OpenFilex.open(file.path);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Open PDF'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e')),
      );
    }
  }

  Future<void> _sendReportOnWhatsApp() async {
    try {
      final file = await _buildCustomerReportPdf(entriesAsc: _allEntriesAsc());
      final number = _sanitizePhoneForWhatsApp(
        (widget.customer['phone'] ?? '').toString(),
      );
      if (!mounted) return;
      if (number.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No number'),
            content: Text(
              "Customer doesn't have number. Report has been downloaded.\n\n"
              'Saved to:\n${file.path}\n\n'
              'To open it:\n'
              '1. Open Files/My Files app\n'
              '2. Go to Android/data/com.example.app/files\n'
              '3. Open the PDF file',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await OpenFilex.open(file.path);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Open PDF'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      final customerName = (widget.customer['name'] ?? 'Customer').toString();
      final message = Uri.encodeComponent(
        'Hi $customerName, please find your account report. '
        'Net balance: AED ${_balance.abs().toStringAsFixed(0)}.',
      );
      final waUri = Uri.parse('https://wa.me/$number?text=$message');
      if (await canLaunchUrl(waUri)) {
        await launchUrl(waUri, mode: LaunchMode.externalApplication);
      }
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Customer report - $customerName',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share report: $e')),
      );
    }
  }

  Future<void> _openAdd(String type) async {
    await _showAddEntrySheet(type);
  }

  Future<void> _showEditCustomerSheet() async {
    final nameController = TextEditingController(
      text: (widget.customer['name'] ?? '').toString(),
    );
    final phoneController = TextEditingController(
      text: (widget.customer['phone'] ?? '').toString(),
    );
    File? pickedPhoto;
    bool saving = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> onPickPhoto() async {
              final picked = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
              );
              if (picked == null) return;
              setSheetState(() {
                pickedPhoto = File(picked.path);
              });
            }

            Future<void> onSave() async {
              if (saving) return;
              final name = nameController.text.trim();
              if (name.isEmpty) {
                setSheetState(() {
                  error = 'Name is required';
                });
                return;
              }
              setSheetState(() {
                saving = true;
                error = null;
              });
              try {
                final updated = await Api.updateCustomer(
                  customerId: widget.customer['id'] as int,
                  name: name,
                  phone: phoneController.text.trim(),
                  photoPath: pickedPhoto?.path,
                );
                if (!mounted) return;
                setState(() {
                  widget.customer['name'] = updated['name'] ?? name;
                  widget.customer['phone'] = updated['phone'];
                  if (updated['photo_url'] != null) {
                    widget.customer['photo_url'] = updated['photo_url'];
                  }
                  if (updated['photo_path'] != null) {
                    widget.customer['photo_path'] = updated['photo_path'];
                  }
                });
                Navigator.pop(ctx);
                await _load();
              } catch (e) {
                setSheetState(() {
                  saving = false;
                  error = 'Failed to update customer';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit Customer',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: 'Customer name',
                            filled: true,
                            fillColor: const Color(0xFFF7F8FA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Phone (optional)',
                            filled: true,
                            fillColor: const Color(0xFFF7F8FA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: onPickPhoto,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0B4F9E),
                            side: const BorderSide(color: Color(0xFF0B4F9E)),
                          ),
                          icon: const Icon(Icons.photo_camera),
                          label: Text(
                            pickedPhoto == null
                                ? 'Change image'
                                : 'Image selected',
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(error!,
                              style: const TextStyle(color: Colors.red)),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: saving ? null : onSave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0B4F9E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(saving ? 'Saving...' : 'Save Changes'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: saving
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                    _deleteCustomerWithConfirmation();
                                  },
                            child: const Text(
                              'Delete customer',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteCustomerWithConfirmation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete customer?'),
        content: const Text('Are you sure you want to delete this customer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final tx = await Api.getCustomerTransactions(
        customerId: widget.customer['id'] as int,
      );
      for (final t in tx) {
        final id = (t as Map)['id'];
        if (id is int) {
          await Api.deleteTransaction(id);
        }
      }
      await Api.deleteCustomer(widget.customer['id'] as int);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete customer')),
      );
    }
  }

  Future<int?> _getActiveBusinessServerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('active_business_server_id');
  }

  Future<void> _showAddEntrySheet(String type) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final dateLabel = DateFormat('dd MMM yyyy');
    DateTime selectedDate = DateTime.now();
    File? attachment;
    String? error;
    bool saving = false;
    final isGave = type == 'CREDIT';

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> onPickAttachment() async {
              final picked = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
              );
              if (picked == null) return;
              setSheetState(() {
                attachment = File(picked.path);
              });
            }

            Future<void> onPickDate() async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: selectedDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null) return;
              setSheetState(() {
                selectedDate = DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  selectedDate.hour,
                  selectedDate.minute,
                );
              });
            }

            Future<void> onSave() async {
              if (saving) return;
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount <= 0) {
                setSheetState(() {
                  error = 'Enter a valid amount';
                });
                return;
              }
              setSheetState(() {
                error = null;
                saving = true;
              });
              try {
                final businessId = await _getActiveBusinessServerId();
                if (businessId == null) {
                  setSheetState(() {
                    error = 'Select a business first';
                    saving = false;
                  });
                  return;
                }
                await Api.createTransaction(
                  businessId: businessId,
                  customerId: widget.customer['id'] as int,
                  amount: amount,
                  type: type,
                  note: noteController.text.trim(),
                  createdAt: selectedDate.toIso8601String(),
                  attachmentPath: attachment?.path,
                );
                if (!mounted) return;
                Navigator.pop(ctx);
                await _load();
              } catch (e) {
                setSheetState(() {
                  error = 'Failed to save entry';
                  saving = false;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isGave
                                    ? const Color(0xFFFDEDED)
                                    : const Color(0xFFE9F7EF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isGave
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                color: isGave ? Colors.red : Colors.green,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isGave
                                  ? 'Add You Gave Entry'
                                  : 'Add You Got Entry',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Amount (AED)',
                            filled: true,
                            fillColor: const Color(0xFFF7F8FA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: noteController,
                          decoration: InputDecoration(
                            labelText: 'Note (optional)',
                            filled: true,
                            fillColor: const Color(0xFFF7F8FA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: onPickDate,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF0B4F9E),
                                  side: const BorderSide(
                                    color: Color(0xFF0B4F9E),
                                  ),
                                ),
                                icon: const Icon(Icons.calendar_today),
                                label: Text(dateLabel.format(selectedDate)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: onPickAttachment,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF0B4F9E),
                                  side: const BorderSide(
                                    color: Color(0xFF0B4F9E),
                                  ),
                                ),
                                icon: const Icon(Icons.attach_file),
                                label: Text(
                                  attachment == null
                                      ? 'Attach image'
                                      : 'Image attached',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: saving ? null : onSave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0B4F9E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(saving ? 'Saving...' : 'Save Entry'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    final name = (widget.customer['name'] ?? '').toString();
    final absBalance = _balance.abs().toStringAsFixed(0);
    final isSettled = _balance == 0;
    final isPositive = _balance > 0;
    final balanceLabel = isSettled
        ? 'Settled up'
        : isPositive
            ? 'You gave'
            : 'You got';
    final balanceColor =
        isSettled ? Colors.black : (isPositive ? Colors.red : Colors.green);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = _dueDate == null
        ? null
        : DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day);
    final dueIsToday = dueDay != null && dueDay == today;
    final dueIsOverdue = dueDay != null && dueDay.isBefore(today);
    final avatar = _partyAvatarProvider();
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _showAvatarPreview,
              child: CircleAvatar(
                backgroundColor: Colors.white,
                backgroundImage: avatar,
                child: avatar == null
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'A',
                        style: const TextStyle(color: brandBlue),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 16)),
                const Text('Customer', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () async {
              final phone = (widget.customer['phone'] ?? '').toString().trim();
              if (phone.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No phone number found.')),
                );
                return;
              }
              final uri = Uri.parse('tel:$phone');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: brandBlue,
            padding: const EdgeInsets.all(12),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(balanceLabel),
                        Text(
                          isSettled ? '0' : 'AED $absBalance',
                          style: TextStyle(
                            color: balanceColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: _dueDate == null
                        ? const Text('Set collection reminder')
                        : Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _dueLabel(),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: (dueIsToday || dueIsOverdue)
                                        ? Colors.red
                                        : Colors.black,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (_overdueDateLabel().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    _overdueDateLabel(),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                    trailing: TextButton(
                      onPressed: _openReminderSheet,
                      child:
                          Text(_dueDate == null ? 'SET DATE' : 'CHANGE DATE'),
                    ),
                    onTap: _openReminderSheet,
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _QuickAction(
                  icon: Icons.picture_as_pdf,
                  label: 'Report',
                  onTap: _downloadCustomerReportPdf,
                ),
                _QuickAction(
                  icon: Icons.edit,
                  label: 'Edit',
                  onTap: _showEditCustomerSheet,
                ),
                if (_balance > 0)
                  _QuickAction(
                    icon: FontAwesomeIcons.whatsapp,
                    label: 'Remind',
                    onTap: () => _shareOnWhatsApp(_balance),
                  ),
                _QuickAction(
                  icon: FontAwesomeIcons.whatsapp,
                  label: 'WhatsApp',
                  onTap: _sendReportOnWhatsApp,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _transactions.isEmpty
                    ? const Center(child: Text('No entries yet.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _transactions.length,
                        itemBuilder: (context, index) {
                          final t = _transactions[index];
                          final amount = _asDouble(t['amount']);
                          final type = (t['type'] ?? '').toString();
                          final running = _asDouble(t['running_balance']);
                          return InkWell(
                            onTap: () {
                              final attachment =
                                  (t['attachment_path'] ?? '').toString();
                              final attachmentUrl = attachment.isNotEmpty
                                  ? (Api.resolveMediaUrl(attachment) ?? '')
                                  : '';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EntryDetailScreen(
                                    title: name,
                                    entry: t,
                                    runningBalance: running,
                                    attachmentUrl: attachmentUrl,
                                    partyImageUrl: Api.resolveMediaUrl(
                                      widget.customer['photo_url'] ??
                                          widget.customer['photoPath'] ??
                                          widget.customer['photo_path'] ??
                                          widget.customer['photo'] ??
                                          widget.customer['image_url'] ??
                                          widget.customer['avatar_url'],
                                    ),
                                    onEdit: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        AppRoutes.onGenerateRoute(
                                          RouteSettings(
                                            name: AppRoutes.addEntry,
                                            arguments: {
                                              'customerId':
                                                  widget.customer['id'],
                                              'transaction': t,
                                            },
                                          ),
                                        ),
                                      ).then((_) => _load());
                                    },
                                    onDelete: () async {
                                      await Api.deleteTransaction(
                                          t['id'] as int);
                                      if (!context.mounted) return;
                                      Navigator.pop(context);
                                      _load();
                                    },
                                  ),
                                ),
                              );
                            },
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(_formatDate(
                                              t['created_at'] as String)),
                                          const SizedBox(height: 6),
                                          Text(
                                              'Bal. AED ${running.toStringAsFixed(0)}'),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 90,
                                    color: type == 'CREDIT'
                                        ? const Color(0xFFFDEDED)
                                        : Colors.transparent,
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      type == 'CREDIT'
                                          ? 'AED ${amount.toStringAsFixed(0)}'
                                          : '',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 90,
                                    color: type == 'DEBIT'
                                        ? const Color(0xFFE9F7EF)
                                        : Colors.transparent,
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      type == 'DEBIT'
                                          ? 'AED ${amount.toStringAsFixed(0)}'
                                          : '',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if ((t['attachment_path'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Icon(Icons.attachment, size: 16),
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
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _openAdd('CREDIT'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('YOU GAVE AED'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _openAdd('DEBIT'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('YOU GOT AED'),
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

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF0B4F9E)),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}
