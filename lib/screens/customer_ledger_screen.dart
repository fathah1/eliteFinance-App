import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
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
      if (!mounted) return;
      setState(() => _dueDate = null);
      return;
    }
    await prefs.setString(key, date.toIso8601String());
    await NotificationService.schedulePaymentReminder(
      id: notifyId,
      title: 'Payment due',
      body: 'Reminder to collect from ${widget.customer['name'] ?? 'customer'}.',
      date: date,
    );
    if (!mounted) return;
    setState(() => _dueDate = date);
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
              final d = DateTime(selected!.year, selected!.month, selected!.day);
              final nw = DateTime(nextWeek.year, nextWeek.month, nextWeek.day);
              final nm = DateTime(nextMonth.year, nextMonth.month, nextMonth.day);
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
                  onChanged: (_) {
                    selected = date;
                    setStateSheet(() {});
                    _saveReminder(date);
                    Navigator.pop(context);
                  },
                ),
                title: Text(label),
                onTap: () {
                  selected = date;
                  setStateSheet(() {});
                  _saveReminder(date);
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
                          firstDate: today.subtract(const Duration(days: 365)),
                          lastDate: today.add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          selected = picked;
                          setStateSheet(() {});
                          _saveReminder(picked);
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
                        firstDate: today.subtract(const Duration(days: 365)),
                        lastDate: today.add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) {
                        selected = picked;
                        setStateSheet(() {});
                        _saveReminder(picked);
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const Divider(height: 24),
                  TextButton(
                    onPressed: () {
                      _saveReminder(null);
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

  Widget _buildRequestCard(
    String name,
    String? phone,
    double amount,
  ) {
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
              child: Text(
                name.trim().isEmpty
                    ? 'C'
                    : name.trim().toUpperCase().substring(0, 1),
                style: const TextStyle(
                  color: Color(0xFF0B4F9E),
                  fontWeight: FontWeight.w600,
                ),
              ),
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
    final file =
        File('${dir.path}/payment_request_${DateTime.now().millisecondsSinceEpoch}.png');
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

  Future<void> _openAdd(String type) async {
    await Navigator.push(
      context,
      AppRoutes.onGenerateRoute(
        RouteSettings(
          name: AppRoutes.addEntry,
          arguments: {
            'customerId': widget.customer['id'],
            'initialType': type,
          },
        ),
      ),
    );
    _load();
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
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'A',
                style: const TextStyle(color: brandBlue),
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
            onPressed: () {},
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
                              const Text('Payment is '),
                              Text(
                                _dueLabel().replaceFirst('Payment is ', ''),
                                style: TextStyle(
                                  color: (dueIsToday || dueIsOverdue)
                                      ? Colors.red
                                      : Colors.black,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_overdueDateLabel().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    _overdueDateLabel(),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                    trailing: TextButton(
                      onPressed: _openReminderSheet,
                      child: const Text('SET DATE'),
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
                const _QuickAction(icon: Icons.picture_as_pdf, label: 'Report'),
                if (_balance > 0)
                  _QuickAction(
                    icon: FontAwesomeIcons.whatsapp,
                    label: 'Remind',
                    onTap: () => _shareOnWhatsApp(_balance),
                  ),
                _QuickAction(
                  icon: Icons.sms,
                  label: 'SMS',
                  onTap: () => _sendSms(_balance),
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
                              final attachment = (t['attachment_path'] ?? '').toString();
                              final attachmentUrl = attachment.isNotEmpty
                                  ? 'https://eliteposs.com/financeserver/public/storage/$attachment'
                                  : '';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EntryDetailScreen(
                                    title: name,
                                    entry: t,
                                    runningBalance: running,
                                    attachmentUrl: attachmentUrl,
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
                                  if ((t['attachment_path'] ?? '').toString().isNotEmpty)
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
