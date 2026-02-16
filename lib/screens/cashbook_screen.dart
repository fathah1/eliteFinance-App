import 'package:flutter/material.dart';

class CashbookScreen extends StatelessWidget {
  const CashbookScreen({
    super.key,
    required this.businessName,
    required this.entries,
  });

  final String businessName;
  final List<Map<String, dynamic>> entries;

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

  bool _isIn(Map<String, dynamic> e) => (e['direction'] ?? 'out') == 'in';

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);

    final sorted = [...entries]
      ..sort((a, b) => _toDate(b['date']).compareTo(_toDate(a['date'])));

    final totalIn = sorted
        .where(_isIn)
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));
    final totalOut = sorted
        .where((e) => !_isIn(e))
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));

    final today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;

    final todayIn = sorted
        .where((e) => _isIn(e) && isToday(_toDate(e['date'])))
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));
    final todayOut = sorted
        .where((e) => !_isIn(e) && isToday(_toDate(e['date'])))
        .fold<double>(0, (s, e) => s + _toDouble(e['amount']));

    final totalBalance = totalIn - totalOut;
    final todayBalance = todayIn - todayOut;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: const Text('Cashbook'),
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
                                  fontSize: 34 / 2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Text('Total Balance'),
                              const SizedBox(height: 8),
                              _mini(
                                left: 'Cash in Hand',
                                right: 'AED ${totalOut.toStringAsFixed(0)}',
                                rightColor: const Color(0xFF12965B),
                              ),
                              const SizedBox(height: 6),
                              _mini(
                                left: 'Online',
                                right: 'AED ${totalIn.toStringAsFixed(0)}',
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
                                  fontSize: 34 / 2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Text("Today's Balance"),
                              const SizedBox(height: 8),
                              _mini(
                                left: 'Cash in Hand',
                                right: 'AED ${todayOut.toStringAsFixed(0)}',
                                rightColor: const Color(0xFFC6284D),
                              ),
                              const SizedBox(height: 6),
                              _mini(
                                left: 'Online',
                                right: 'AED ${todayIn.toStringAsFixed(0)}',
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
                    label: const Text(
                      'VIEW CASHBOOK REPORT',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: sorted.isEmpty
                ? const Center(child: Text('No cashbook entries yet'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final e = sorted[index];
                      final date = _toDate(e['date']);
                      final amount = _toDouble(e['amount']);
                      final isInEntry = _isIn(e);
                      final label = (e['label'] ?? '').toString();
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _time(date),
                                      style: const TextStyle(
                                          color: Colors.black54),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF4F4F4),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Text(label),
                                    ),
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
                                  fontSize: 34 / 2,
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
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDD123E),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 56),
                  ),
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('OUT',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF12965B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 56),
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
    final h = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final m = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $suffix';
  }
}
