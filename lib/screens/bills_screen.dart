import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import 'add_expense_screen.dart';
import 'add_purchase_screen.dart';
import 'add_sale_bill_screen.dart';
import 'cashbook_screen.dart';
import 'expense_detail_screen.dart';

class _BillEntry {
  _BillEntry({
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
    this.extraInfo,
  });

  final int id;
  final String type; // sale|payment_in|purchase|payment_out|expense
  final String partyName;
  final String label;
  final int billNumber;
  final DateTime date;
  final double amount;
  final String paymentMode;
  final String paymentStatusLabel;
  final Color statusColor;
  final String? extraInfo;
}

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  String _tab = 'sale';
  String _query = '';
  String _businessName = 'Business';
  bool _loading = true;

  final List<_BillEntry> _entries = [];

  int _nextSaleNo = 1;
  int _nextPurchaseNo = 1;
  int _nextExpenseNo = 1;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  double _toDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  int _nextNo(String type) {
    final rows = _entries.where((e) => e.type == type).toList();
    if (rows.isEmpty) return 1;
    final maxNo = rows.map((e) => e.billNumber).reduce((a, b) => a > b ? a : b);
    return maxNo + 1;
  }

  Future<void> _loadAll() async {
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
        _nextSaleNo = 1;
        _nextPurchaseNo = 1;
        _nextExpenseNo = 1;
        _loading = false;
      });
      return;
    }

    try {
      final sales = await Api.getSales(businessId: businessId);
      final purchases = await Api.getPurchases(businessId: businessId);
      final expenses = await Api.getExpenses(businessId: businessId);

      final mapped = <_BillEntry>[];

      for (final raw in sales) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _toInt(m['id']);
        final number = _toInt(m['bill_number']);
        final date =
            DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now();
        final party = ((m['party_name'] ?? '').toString().trim().isEmpty)
            ? 'Walk-in Sale'
            : (m['party_name'] ?? '').toString();
        final total = _toDouble(m['total_amount']);
        final received = _toDouble(m['received_amount']);
        final mode = (m['payment_mode'] ?? 'unpaid').toString();
        final unpaid = mode == 'unpaid';

        mapped.add(
          _BillEntry(
            id: id,
            type: 'sale',
            partyName: party,
            label: 'Sale Bill #$number',
            billNumber: number,
            date: date,
            amount: total,
            paymentMode: mode,
            paymentStatusLabel: unpaid ? 'Unpaid' : 'Fully Paid',
            statusColor:
                unpaid ? const Color(0xFFC6284D) : const Color(0xFF12965B),
          ),
        );

        if (received > 0) {
          mapped.add(
            _BillEntry(
              id: id,
              type: 'payment_in',
              partyName: party,
              label: 'Payment In #$number',
              billNumber: number,
              date: date,
              amount: received,
              paymentMode: mode,
              paymentStatusLabel: mode == 'card' ? 'Card' : 'Cash',
              statusColor: Colors.black87,
            ),
          );
        }
      }

      for (final raw in purchases) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _toInt(m['id']);
        final number = _toInt(m['purchase_number']);
        final date =
            DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now();
        final party = ((m['party_name'] ?? '').toString().trim().isEmpty)
            ? 'Walk-in Purchase'
            : (m['party_name'] ?? '').toString();
        final total = _toDouble(m['total_amount']);
        final paid = _toDouble(m['paid_amount']);
        final mode = (m['payment_mode'] ?? 'unpaid').toString();
        final unpaid = mode == 'unpaid';

        mapped.add(
          _BillEntry(
            id: id,
            type: 'purchase',
            partyName: party,
            label: 'Purchase #$number',
            billNumber: number,
            date: date,
            amount: total,
            paymentMode: mode,
            paymentStatusLabel: unpaid ? 'Unpaid' : 'Fully Paid',
            statusColor:
                unpaid ? const Color(0xFFC6284D) : const Color(0xFF12965B),
          ),
        );

        if (paid > 0) {
          mapped.add(
            _BillEntry(
              id: id,
              type: 'payment_out',
              partyName: party,
              label: 'Payment Out #$number',
              billNumber: number,
              date: date,
              amount: paid,
              paymentMode: mode,
              paymentStatusLabel: mode == 'card' ? 'Card' : 'Cash',
              statusColor: Colors.black87,
            ),
          );
        }
      }

      for (final raw in expenses) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _toInt(m['id']);
        final number = _toInt(m['expense_number']);
        final date =
            DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now();
        final amount = _toDouble(m['amount']);
        final category = (m['category_name'] ?? '').toString().trim();
        final items = (m['items'] as List?) ?? const [];
        final names = items
            .map((e) =>
                (Map<String, dynamic>.from(e as Map)['name'] ?? '').toString())
            .where((e) => e.trim().isNotEmpty)
            .join(', ');
        final info = [
          if (category.isNotEmpty) category,
          if (names.isNotEmpty) names,
        ].join(' • ');

        mapped.add(
          _BillEntry(
            id: id,
            type: 'expense',
            partyName: 'Expense',
            label: 'Expense #$number',
            billNumber: number,
            date: date,
            amount: amount,
            paymentMode: 'expense',
            paymentStatusLabel: '',
            statusColor: Colors.black87,
            extraInfo: info.isEmpty ? null : info,
          ),
        );
      }

      mapped.sort((a, b) => b.date.compareTo(a.date));

      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(mapped);
        _nextSaleNo = _nextNo('sale');
        _nextPurchaseNo = _nextNo('purchase');
        _nextExpenseNo = _nextNo('expense');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not refresh bills: $e')));
    }
  }

  List<_BillEntry> get _filtered {
    Iterable<_BillEntry> rows;
    if (_tab == 'sale') {
      rows = _entries.where((e) => e.type == 'sale' || e.type == 'payment_in');
    } else if (_tab == 'purchase') {
      rows = _entries
          .where((e) => e.type == 'purchase' || e.type == 'payment_out');
    } else {
      rows = _entries.where((e) => e.type == 'expense');
    }

    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return rows.toList();

    return rows.where((e) {
      return e.partyName.toLowerCase().contains(q) ||
          e.label.toLowerCase().contains(q) ||
          e.billNumber.toString().contains(q) ||
          (e.extraInfo ?? '').toLowerCase().contains(q);
    }).toList();
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  double get _monthlySales =>
      _entries.where((e) => e.type == 'sale').fold(0, (s, e) => s + e.amount);

  double get _monthlyPurchases => _entries
      .where((e) => e.type == 'purchase')
      .fold(0, (s, e) => s + e.amount);

  double get _todayIn => _entries
      .where((e) => e.type == 'payment_in' && _isToday(e.date))
      .fold(0, (s, e) => s + e.amount);

  double get _todayOut => _entries
      .where((e) =>
          (e.type == 'payment_out' || e.type == 'expense') && _isToday(e.date))
      .fold(0, (s, e) => s + e.amount);

  Future<void> _openSale() async {
    final draft = await Navigator.push<SaleBillDraft>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddSaleBillScreen(billNumber: _nextSaleNo <= 0 ? 1 : _nextSaleNo),
      ),
    );
    if (draft?.saved == true) await _loadAll();
  }

  Future<void> _openPurchase() async {
    final draft = await Navigator.push<PurchaseDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPurchaseScreen(
          purchaseNumber: _nextPurchaseNo <= 0 ? 1 : _nextPurchaseNo,
        ),
      ),
    );
    if (draft?.saved == true) await _loadAll();
  }

  Future<void> _openExpense() async {
    final draft = await Navigator.push<ExpenseDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          expenseNumber: _nextExpenseNo <= 0 ? 1 : _nextExpenseNo,
        ),
      ),
    );
    if (draft?.saved == true) await _loadAll();
  }

  Future<void> _openExpenseDetails(_BillEntry entry) async {
    final draft = await Navigator.push<ExpenseDraft>(
      context,
      MaterialPageRoute(
          builder: (_) => ExpenseDetailScreen(expenseId: entry.id)),
    );
    if (draft?.saved == true) await _loadAll();
  }

  void _openCashbook() {
    final rows = _entries
        .where((e) =>
            e.type == 'payment_in' ||
            e.type == 'payment_out' ||
            e.type == 'expense')
        .map((e) => {
              'date': e.date,
              'label': e.type == 'payment_in'
                  ? 'Payment In'
                  : e.type == 'payment_out'
                      ? 'Payment Out'
                      : 'Expense',
              'amount': e.amount,
              'direction': e.type == 'payment_in' ? 'in' : 'out',
            })
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashbookScreen(
          businessName: _businessName,
          entries: rows,
        ),
      ),
    );
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
                children: [
                  _MoreAction(
                    icon: Icons.note_alt_outlined,
                    label: _tab == 'purchase' ? 'Purchase' : 'Sale',
                    bg: const Color(0xFFE9F5ED),
                    fg: const Color(0xFF12965B),
                  ),
                  _MoreAction(
                    icon: Icons.assignment_return_outlined,
                    label:
                        _tab == 'purchase' ? 'Purchase Return' : 'Sale Return',
                    bg: const Color(0xFFF9F6DE),
                    fg: const Color(0xFFA88E1F),
                  ),
                  _MoreAction(
                    icon: Icons.currency_exchange,
                    label: _tab == 'purchase' ? 'Payment Out' : 'Payment In',
                    bg: _tab == 'purchase'
                        ? const Color(0xFFFCEAF0)
                        : const Color(0xFFE9F5ED),
                    fg: _tab == 'purchase'
                        ? const Color(0xFFC2185B)
                        : const Color(0xFF12965B),
                  ),
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _tab == 'purchase'
                            ? 'Sale, Payment In, Sale Return'
                            : 'Purchase, Payment Out, Purchase Return',
                      ),
                    ),
                    const Icon(Icons.chevron_right),
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
                    Text(
                      _businessName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
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
                        const Color(0xFF12965B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _topStatCard(
                        'AED ${_monthlyPurchases.toStringAsFixed(0)}',
                        'Monthly Purchases',
                        const Color(0xFFC6284D),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _reportsCard()),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: InkWell(
                    onTap: _openCashbook,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            children: [
                              Text(
                                'AED ${_todayIn.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text("Today's IN",
                                  style: TextStyle(color: Colors.black54)),
                            ],
                          ),
                          Column(
                            children: [
                              Text(
                                'AED ${_todayOut.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text("Today's OUT",
                                  style: TextStyle(color: Colors.black54)),
                            ],
                          ),
                          const Text(
                            'CASHBOOK >',
                            style: TextStyle(
                                color: brandBlue, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                                            : 'Search for Expenses',
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
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _filtered.isEmpty
                          ? Center(
                              child: Text(
                                _tab == 'sale'
                                    ? 'No sale bills yet'
                                    : _tab == 'purchase'
                                        ? 'No purchase bills yet'
                                        : 'No expenses yet',
                              ),
                            )
                          : ListView.builder(
                              itemCount: _filtered.length,
                              padding: const EdgeInsets.only(bottom: 90),
                              itemBuilder: (context, index) {
                                final e = _filtered[index];
                                return InkWell(
                                  onTap: e.type == 'expense'
                                      ? () => _openExpenseDetails(e)
                                      : null,
                                  child: _entryTile(e),
                                );
                              },
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
                      Text(
                        'MORE',
                        style: TextStyle(
                          color: Color(0xFF1D2A8D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
                  onPressed: _tab == 'sale'
                      ? _openSale
                      : _tab == 'purchase'
                          ? _openPurchase
                          : _openExpense,
                  icon: Icon(
                    _tab == 'expense'
                        ? Icons.money_off_csred_outlined
                        : Icons.note_add_outlined,
                  ),
                  label: Text(
                    _tab == 'sale'
                        ? 'ADD BILL'
                        : _tab == 'purchase'
                            ? 'ADD PURCHASE'
                            : 'ADD EXPENSE',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
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

  Widget _entryTile(_BillEntry e) {
    const brandBlue = Color(0xFF0B4F9E);

    IconData icon;
    Color bg;
    Color fg;
    switch (e.type) {
      case 'sale':
        icon = Icons.receipt_long;
        bg = const Color(0xFFEAF2FF);
        fg = brandBlue;
        break;
      case 'purchase':
        icon = Icons.shopping_cart_outlined;
        bg = const Color(0xFFF3F2FF);
        fg = const Color(0xFF4B5DA8);
        break;
      case 'payment_out':
      case 'expense':
        icon = Icons.currency_rupee;
        bg = const Color(0xFFFCEAF0);
        fg = const Color(0xFFC2185B);
        break;
      case 'payment_in':
      default:
        icon = Icons.currency_rupee;
        bg = const Color(0xFFE8F7EC);
        fg = const Color(0xFF12965B);
        break;
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: bg,
            child: Icon(icon, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.partyName,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    e.label,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${e.date.day.toString().padLeft(2, '0')} ${_month(e.date.month)} ${e.date.year.toString().substring(2)}',
                  style: const TextStyle(color: Colors.black54),
                ),
                if (e.extraInfo != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    e.extraInfo!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'AED ${e.amount.toStringAsFixed(0)}',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
              ),
              const SizedBox(height: 8),
              if (e.paymentStatusLabel.isNotEmpty)
                Text(
                  e.paymentStatusLabel,
                  style: TextStyle(
                      color: e.statusColor, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ],
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
            Text(
              value,
              style: TextStyle(
                  color: valueColor, fontSize: 14, fontWeight: FontWeight.w700),
            ),
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
            Text(
              'VIEW\nREPORTS',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF0B4F9E),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 3),
            Icon(Icons.chevron_right, color: Color(0xFF0B4F9E)),
          ],
        ),
      ),
    );
  }
}

class _MoreAction extends StatelessWidget {
  const _MoreAction({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
            radius: 26, backgroundColor: bg, child: Icon(icon, color: fg)),
        const SizedBox(height: 8),
        Text(label),
      ],
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
