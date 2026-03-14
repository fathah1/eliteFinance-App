import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import 'cashbook_entry_screen.dart';

class CashbookScreen extends StatefulWidget {
  const CashbookScreen({
    super.key,
    required this.businessId,
    required this.businessName,
    this.title = 'Cashbook',
    this.reportButtonText = 'VIEW CASHBOOK REPORT',
    this.modeFilter = 'all', // all|cash|card
  });

  final int businessId;
  final String businessName;
  final String title;
  final String reportButtonText;
  final String modeFilter;

  @override
  State<CashbookScreen> createState() => _CashbookScreenState();
}

class _CashbookScreenState extends State<CashbookScreen> {
  static const brandBlue = Color(0xFF0B4F9E);
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  DateTime _toDate(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse((value ?? '').toString()) ?? DateTime.now();
  }

  DateTime _entryDate(Map<String, dynamic> e) {
    return _toDate(e['created_at'] ?? e['updated_at'] ?? e['date']);
  }

  bool _isIn(Map<String, dynamic> e) => (e['direction'] ?? 'out') == 'in';

  bool _isCard(Map<String, dynamic> e) {
    final mode = (e['payment_mode'] ?? '').toString().toLowerCase();
    return mode == 'card' || mode == 'online';
  }

  List<Map<String, dynamic>> _filteredEntries() {
    if (widget.modeFilter == 'card') {
      return _entries.where(_isCard).toList();
    }
    if (widget.modeFilter == 'cash') {
      return _entries.where((e) => !_isCard(e)).toList();
    }
    return _entries;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Api.getCashbook(businessId: widget.businessId);
      final rows = (data['entries'] as List?) ?? const [];
      setState(() {
        _entries = rows.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _openEntry(String direction) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CashbookEntryScreen(
          businessId: widget.businessId,
          direction: direction,
          defaultPaymentMode: widget.modeFilter == 'card' ? 'card' : 'cash',
          titlePrefix:
              direction == 'in' ? 'IN entry of' : 'OUT entry of',
        ),
      ),
    );
    if (ok == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [..._filteredEntries()]
      ..sort((a, b) {
        final dateCmp = _entryDate(b).compareTo(_entryDate(a));
        if (dateCmp != 0) return dateCmp;
        final idA = int.tryParse((a['id'] ?? 0).toString()) ?? 0;
        final idB = int.tryParse((b['id'] ?? 0).toString()) ?? 0;
        return idB.compareTo(idA);
      });

    final totalIn = sorted
        .where(_isIn)
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));
    final totalOut = sorted
        .where((e) => !_isIn(e))
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));
    final totalBalance = totalIn - totalOut;

    final cashIn = sorted
        .where((e) => _isIn(e) && !_isCard(e))
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));
    final cashOut = sorted
        .where((e) => !_isIn(e) && !_isCard(e))
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));
    final cardIn = sorted
        .where((e) => _isIn(e) && _isCard(e))
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));
    final cardOut = sorted
        .where((e) => !_isIn(e) && _isCard(e))
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));

    final today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;

    final todayIn = sorted
        .where((e) => _isIn(e) && isToday(_entryDate(e)))
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));
    final todayOut = sorted
        .where((e) => !_isIn(e) && isToday(_entryDate(e)))
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));
    final todayBalance = todayIn - todayOut;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: brandBlue,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'AED ${totalBalance.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Color(0xFF12965B),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Text('Total Balance'),
                              const SizedBox(height: 8),
                              _mini(
                                left: 'Cash in Hand',
                                right:
                                    'AED ${(cashIn - cashOut).toStringAsFixed(0)}',
                                rightColor: const Color(0xFF12965B),
                              ),
                              const SizedBox(height: 6),
                              _mini(
                                left: 'Online',
                                right:
                                    'AED ${(cardIn - cardOut).toStringAsFixed(0)}',
                                rightColor: const Color(0xFF12965B),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 110, color: Colors.black12),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'AED ${todayBalance.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Color(0xFFC6284D),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Text("Today's Balance"),
                              const SizedBox(height: 8),
                              _mini(
                                left: 'Cash in Hand',
                                right:
                                    'AED ${(todayIn - todayOut).toStringAsFixed(0)}',
                                rightColor: const Color(0xFFC6284D),
                              ),
                              const SizedBox(height: 6),
                              _mini(
                                left: 'Online',
                                right:
                                    'AED ${todayIn.toStringAsFixed(0)}',
                                rightColor: Colors.black87,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.description_outlined),
                    label: Text(
                      widget.reportButtonText,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : sorted.isEmpty
                    ? const Center(child: Text('No cashbook entries yet'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                          itemCount: sorted.length,
                          itemBuilder: (context, index) {
                            final e = sorted[index];
                            final date = _entryDate(e);
                            final amount = _toDouble(e['amount']);
                            final isInEntry = _isIn(e);
                            final label =
                                (e['note'] ?? e['label'] ?? '').toString();
                            final photoUrl =
                                (e['photo_url'] ?? '').toString().trim();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
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
                                          Text(
                                            _time(date),
                                            style: const TextStyle(
                                                color: Colors.black54),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            label.isEmpty
                                                ? (isInEntry
                                                    ? 'Payment In'
                                                    : 'Payment Out')
                                                : label,
                                          ),
                                          if (photoUrl.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            GestureDetector(
                                              onTap: () => _previewImage(
                                                  context, photoUrl),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.network(
                                                  photoUrl,
                                                  width: 46,
                                                  height: 46,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context,
                                                      error, stackTrace) {
                                                    return Container(
                                                      width: 46,
                                                      height: 46,
                                                      color: const Color(
                                                          0xFFF0F0F0),
                                                      child: const Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                        size: 20,
                                                        color: Colors.black45,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 120,
                                    height: 92,
                                    color: isInEntry
                                        ? const Color(0xFFEAF8EE)
                                        : const Color(0xFFFDEFF2),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'AED ${amount.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        color: isInEntry
                                            ? const Color(0xFF12965B)
                                            : const Color(0xFFC6284D),
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFFF1F3F6),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openEntry('out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDD123E),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 60),
                  ),
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('OUT',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openEntry('in'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF12965B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 60),
                  ),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('IN',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _mini({
    required String left,
    required String right,
    required Color rightColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(left)),
          Text(
            right,
            style: TextStyle(color: rightColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _time(DateTime date) {
    return DateFormat('dd MMM yyyy • h:mm a').format(date);
  }

  void _previewImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: InteractiveViewer(
            maxScale: 4,
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(Icons.broken_image_outlined),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
