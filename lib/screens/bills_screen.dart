import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import 'add_sale_bill_screen.dart';

class _SaleBill {
  _SaleBill({
    required this.id,
    required this.type,
    required this.partyName,
    required this.label,
    required this.billNumber,
    required this.date,
    required this.amount,
    required this.paymentMode,
    required this.paymentStatusLabel,
    required this.statusColor,
  });

  final int id;
  final String type; // sale | payment_in
  final String partyName;
  final String label;
  final int billNumber;
  final DateTime date;
  final double amount;
  final String paymentMode;
  final String paymentStatusLabel;
  final Color statusColor;
}

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  String _tab = 'sale';
  String _query = '';
  int _nextBillNo = 1;
  String _businessName = 'Business';
  bool _loading = true;
  final List<_SaleBill> _sales = [];

  @override
  void initState() {
    super.initState();
    _loadBusinessAndSales();
  }

  int get _draftBillNo => _nextBillNo <= 0 ? 1 : _nextBillNo;

  int _computeNextBillNo() {
    final saleRows = _sales.where((e) => e.type == 'sale').toList();
    if (saleRows.isEmpty) return 1;
    final maxNo =
        saleRows.map((e) => e.billNumber).reduce((a, b) => a > b ? a : b);
    return maxNo + 1;
  }

  List<_SaleBill> get _filteredSales {
    if (_query.trim().isEmpty) return _sales;
    final q = _query.toLowerCase();
    return _sales.where((b) {
      return b.partyName.toLowerCase().contains(q) ||
          b.label.toLowerCase().contains(q) ||
          b.billNumber.toString().contains(q);
    }).toList();
  }

  double get _monthlySales => _sales
      .where((e) => e.type == 'sale')
      .fold<double>(0, (sum, b) => sum + b.amount);

  Future<void> _loadBusinessAndSales() async {
    final prefs = await SharedPreferences.getInstance();
    final businessName =
        prefs.getString('active_business_name')?.trim().isNotEmpty == true
            ? prefs.getString('active_business_name')!.trim()
            : 'Business';
    final businessId = prefs.getInt('active_business_server_id');
    if (!mounted) return;
    setState(() {
      _businessName = businessName;
      _loading = true;
    });
    if (businessId == null) {
      if (!mounted) return;
      setState(() {
        _sales.clear();
        _nextBillNo = 1;
        _loading = false;
      });
      return;
    }
    try {
      final rows = await Api.getSales(businessId: businessId);
      if (!mounted) return;
      final mapped = <_SaleBill>[];
      for (final raw in rows) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = (m['id'] as num?)?.toInt() ?? 0;
        final billNumber = (m['bill_number'] as num?)?.toInt() ?? 0;
        final date =
            DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now();
        final party = ((m['party_name'] ?? '').toString().trim().isEmpty)
            ? 'Walk-in Sale'
            : (m['party_name'] ?? '').toString();
        final total = (m['total_amount'] as num?)?.toDouble() ??
            double.tryParse((m['total_amount'] ?? '0').toString()) ??
            0;
        final received = (m['received_amount'] as num?)?.toDouble() ??
            double.tryParse((m['received_amount'] ?? '0').toString()) ??
            0;
        final paymentMode = (m['payment_mode'] ?? 'unpaid').toString();
        final isUnpaid = paymentMode == 'unpaid';
        mapped.add(
          _SaleBill(
            id: id,
            type: 'sale',
            partyName: party,
            label: 'Sale Bill #$billNumber',
            billNumber: billNumber,
            date: date,
            amount: total,
            paymentMode: paymentMode,
            paymentStatusLabel: isUnpaid ? 'Unpaid' : 'Fully Paid',
            statusColor: isUnpaid ? Colors.red.shade700 : Colors.green,
          ),
        );
        if (received > 0) {
          mapped.add(
            _SaleBill(
              id: id,
              type: 'payment_in',
              partyName: party,
              label: 'Payment In #$billNumber',
              billNumber: billNumber,
              date: date,
              amount: received,
              paymentMode: paymentMode,
              paymentStatusLabel: paymentMode == 'card' ? 'Card' : 'Cash',
              statusColor: Colors.black87,
            ),
          );
        }
      }
      mapped.sort((a, b) => b.date.compareTo(a.date));
      setState(() {
        _sales
          ..clear()
          ..addAll(mapped);
        _nextBillNo = _computeNextBillNo();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sales.clear();
        _nextBillNo = 1;
        _loading = false;
      });
    }
  }

  Future<void> _openAddSaleBill() async {
    final draft = await Navigator.push<SaleBillDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => AddSaleBillScreen(billNumber: _draftBillNo),
      ),
    );
    if (draft == null || draft.saved != true) return;
    await _loadBusinessAndSales();
  }

  Future<void> _openMoreSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: const [
                  _MoreAction(icon: Icons.note_alt_outlined, label: 'Sale'),
                  _MoreAction(
                      icon: Icons.assignment_return_outlined,
                      label: 'Sale Return'),
                  _MoreAction(
                      icon: Icons.currency_exchange, label: 'Payment In'),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black26),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Purchase, Payment Out, Purchase Return',
                        style: TextStyle(fontSize: 18 / 1.15),
                      ),
                    ),
                    Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      body: Column(
        children: [
          Container(
            color: brandBlue,
            padding: const EdgeInsets.fromLTRB(12, 46, 12, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.storefront_outlined, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(_businessName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 32 / 2)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _topStatCard(
                          'AED ${_monthlySales.toStringAsFixed(0)}',
                          'Monthly Sales',
                          Colors.green),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _topStatCard(
                          'AED 0', 'Monthly Purchases', Colors.red),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _reportsCard(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Column(
                                children: [
                                  Text('AED 0',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 18)),
                                  SizedBox(height: 2),
                                  Text("Today's IN",
                                      style: TextStyle(color: Colors.black54)),
                                ],
                              ),
                              Column(
                                children: [
                                  Text('AED 0',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 18)),
                                  SizedBox(height: 2),
                                  Text("Today's OUT",
                                      style: TextStyle(color: Colors.black54)),
                                ],
                              ),
                              Text('CASHBOOK >',
                                  style: TextStyle(
                                      color: brandBlue,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _billTab('sale', 'Sale'),
                    _billTab('purchase', 'Purchase'),
                    _billTab('expense', 'Expense'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: Colors.black45),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  onChanged: (v) => setState(() => _query = v),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: _tab == 'sale'
                                        ? 'Search for sales transactions'
                                        : _tab == 'purchase'
                                            ? 'Search for purchase transactions'
                                            : 'Search for expense transactions',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.filter_alt_outlined,
                          color: brandBlue, size: 28),
                      const SizedBox(width: 10),
                      const Icon(Icons.sort, color: brandBlue, size: 28),
                    ],
                  ),
                ),
                Expanded(
                  child: _tab == 'sale'
                      ? _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _filteredSales.isEmpty
                              ? const Center(child: Text('No sale bills yet'))
                              : ListView.builder(
                                  itemCount: _filteredSales.length,
                                  itemBuilder: (context, index) {
                                    final b = _filteredSales[index];
                                    return Container(
                                      color: Colors.white,
                                      padding: const EdgeInsets.all(12),
                                      margin: const EdgeInsets.only(bottom: 1),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 24,
                                            backgroundColor: b.type == 'sale'
                                                ? const Color(0xFFEAF2FF)
                                                : const Color(0xFFE8F7EC),
                                            child: Icon(
                                              b.type == 'sale'
                                                  ? Icons.receipt_long
                                                  : Icons.currency_rupee,
                                              color: b.type == 'sale'
                                                  ? brandBlue.withValues(
                                                      alpha: 0.9)
                                                  : const Color(0xFF12965B),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(b.partyName,
                                                    style: const TextStyle(
                                                        fontSize: 20 / 1.2,
                                                        fontWeight:
                                                            FontWeight.w500)),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFFF2F2F2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: Text(
                                                    b.label,
                                                    style: const TextStyle(
                                                        color: Colors.black54),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${b.date.day} ${_month(b.date.month)} ${b.date.year.toString().substring(2)}',
                                                  style: const TextStyle(
                                                      color: Colors.black54),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                  'AED ${b.amount.toStringAsFixed(0)}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 18)),
                                              const SizedBox(height: 8),
                                              Text(
                                                b.paymentStatusLabel,
                                                style: TextStyle(
                                                  color: b.statusColor,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          )
                                        ],
                                      ),
                                    );
                                  },
                                )
                      : Center(
                          child: Text(
                            _tab == 'purchase'
                                ? 'Purchase section next'
                                : 'Expense section next',
                          ),
                        ),
                ),
              ],
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
                child: OutlinedButton(
                  onPressed: _openMoreSheet,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1D2A8D)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('MORE',
                          style: TextStyle(
                              color: Color(0xFF1D2A8D),
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text('Payment & Return',
                          style: TextStyle(color: Color(0xFF1D2A8D))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _tab == 'sale' ? _openAddSaleBill : null,
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('ADD BILL',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D2A8D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _billTab(String key, String label) {
    final selected = _tab == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = key),
        child: Container(
          padding: const EdgeInsets.only(bottom: 10, top: 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      ),
    );
  }

  Widget _topStatCard(String value, String title, Color valueColor) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: valueColor,
                    fontSize: 28 / 2,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(title, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _reportsCard() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text('VIEW\nREPORTS',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFF0B4F9E),
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 3),
            Icon(Icons.chevron_right, color: Color(0xFF0B4F9E)),
          ],
        ),
      ),
    );
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

class _MoreAction extends StatelessWidget {
  const _MoreAction({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFFE9F5ED),
          child: Icon(icon, color: const Color(0xFF12965B)),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}
