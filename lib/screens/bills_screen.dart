import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../access_control.dart';
import '../api.dart';
import '../app_events.dart';
import 'add_expense_screen.dart';
import 'add_bill_payment_screen.dart';
import 'add_bill_return_screen.dart';
import 'add_purchase_screen.dart';
import 'add_sale_bill_screen.dart';
import 'bill_detail_screen.dart';
import 'cashbook_screen.dart';
import 'expense_detail_screen.dart';
import 'payment_detail_screen.dart';
import '../routes.dart';
import '../widgets/app_brand_logo.dart';
import '../widgets/sync_status_chip.dart';

class _BillEntry {
  _BillEntry({
    required this.id,
    required this.type,
    required this.partyName,
    required this.label,
    required this.billNumber,
    required this.date,
    required this.sortDate,
    required this.sortId,
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
  final DateTime sortDate;
  final int sortId;
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
  int? _activeBusinessId;
  String _tab = 'sale';
  String _query = '';
  String _businessName = 'Business';
  bool _loading = true;
  Map<String, dynamic>? _user;

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

  DateTime _serverSortDate({
    required String? createdAt,
    required String? updatedAt,
    required String? date,
    required int id,
  }) {
    DateTime? parse(String? raw) =>
        raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
    final c = parse(createdAt);
    final u = parse(updatedAt);
    final d = parse(date);
    bool hasTime(String? raw) =>
        raw != null && (raw.contains('T') || raw.contains(':'));

    DateTime picked;
    if (c != null && hasTime(createdAt)) {
      picked = c;
    } else if (u != null && hasTime(updatedAt)) {
      picked = u;
    } else if (d != null) {
      picked = d.add(Duration(seconds: id % 86400));
    } else {
      picked = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return picked.toUtc();
  }

  int _nextNo(String type) {
    final rows = _entries.where((e) => e.type == type).toList();
    if (rows.isEmpty) return 1;
    final maxNo = rows.map((e) => e.billNumber).reduce((a, b) => a > b ? a : b);
    return maxNo + 1;
  }

  int _nextNoFromPrefix(String prefix) {
    final re = RegExp('^${RegExp.escape(prefix)} #(\\d+)');
    var maxNo = 0;
    for (final e in _entries) {
      final m = re.firstMatch(e.label);
      if (m == null) continue;
      final n = int.tryParse(m.group(1) ?? '');
      if (n != null && n > maxNo) maxNo = n;
    }
    return maxNo + 1;
  }

  double _billTotal(Map<String, dynamic> m) {
    final total = _toDouble(m['total_amount']);
    if (total > 0) return total;
    final manual = _toDouble(m['manual_amount']);
    if (manual > 0) return manual;
    return _toDouble(m['amount']);
  }

  int _parseBillNoFromNote(String note, String prefix) {
    if (!note.startsWith(prefix)) return 0;
    final m = RegExp('#(\\d+)').firstMatch(note);
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  int _safeBillNo(Map<String, dynamic> m, String key) {
    final n = _toInt(m[key]);
    return n > 0 ? n : 1;
  }

  Map<String, dynamic> _paymentStatus({
    required double total,
    required double paid,
    required double balance,
  }) {
    if (total <= 0) {
      return {
        'label': 'Fully Paid',
        'color': const Color(0xFF12965B),
      };
    }
    if (balance > 0) {
      if (paid > 0) {
        return {
          'label': 'Partially Paid',
          'color': const Color(0xFFE67E22),
        };
      }
      return {
        'label': 'Unpaid',
        'color': const Color(0xFFC6284D),
      };
    }
    return {
      'label': 'Fully Paid',
      'color': const Color(0xFF12965B),
    };
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getInt('active_business_server_id');
    final businessName = prefs.getString('active_business_name')?.trim();
    final user = await Api.getUser();

    if (!mounted) return;
    setState(() {
      _businessName = (businessName == null || businessName.isEmpty)
          ? 'Business'
          : businessName;
      _activeBusinessId = businessId;
      _user = user;
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
      final saleReturns = await Api.getSaleReturns(businessId: businessId);
      final purchaseReturns =
          await Api.getPurchaseReturns(businessId: businessId);
      final expenses = await Api.getExpenses(businessId: businessId);
      final allCustomerTx =
          await Api.getAllTransactions(businessId: businessId);
      final allSupplierTx =
          await Api.getAllSupplierTransactions(businessId: businessId);
      final customers = await Api.getCustomers(businessId: businessId);
      final suppliers = await Api.getSuppliers(businessId: businessId);

      final customerNameById = <int, String>{
        for (final c in customers)
          _toInt((c as Map)['id']):
              (((c)['name'] ?? '').toString().trim().isEmpty)
                  ? 'Customer'
                  : ((c)['name'] ?? '').toString(),
      };
      final supplierNameById = <int, String>{
        for (final s in suppliers)
          _toInt((s as Map)['id']):
              (((s)['name'] ?? '').toString().trim().isEmpty)
                  ? 'Supplier'
                  : ((s)['name'] ?? '').toString(),
      };

      final mapped = <_BillEntry>[];
      final paymentInBillNos = <int>{};
      final paymentOutBillNos = <int>{};
      final paymentInTotals = <int, double>{};
      final paymentOutTotals = <int, double>{};
      final saleIdToBillNo = <int, int>{};
      final purchaseIdToBillNo = <int, int>{};

      for (final raw in sales) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _toInt(m['id']);
        final number = _safeBillNo(m, 'bill_number');
        saleIdToBillNo[id] = number;
      }

      for (final raw in purchases) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _toInt(m['id']);
        final number = _safeBillNo(m, 'purchase_number');
        purchaseIdToBillNo[id] = number;
      }

      for (final raw in allCustomerTx) {
        final m = Map<String, dynamic>.from(raw as Map);
        final note = (m['note'] ?? '').toString();
        if (!note.startsWith('Payment In #')) continue;
        final saleIds =
            (m['sale_ids'] as List?)?.map((e) => (e as num).toInt()).toList() ??
                const <int>[];
        final saleId =
            (m['sale_id'] is num) ? (m['sale_id'] as num).toInt() : 0;
        final linkedIds = <int>[
          ...saleIds,
          if (saleId > 0) saleId,
        ];
        if (linkedIds.isNotEmpty) {
          for (final id in linkedIds) {
            final billNo = saleIdToBillNo[id] ?? 0;
            if (billNo <= 0) continue;
            paymentInBillNos.add(billNo);
            paymentInTotals[billNo] =
                (paymentInTotals[billNo] ?? 0) + _toDouble(m['amount']);
          }
        } else {
          final billNo = _parseBillNoFromNote(note, 'Payment In #');
          if (billNo <= 0) continue;
          paymentInBillNos.add(billNo);
          paymentInTotals[billNo] =
              (paymentInTotals[billNo] ?? 0) + _toDouble(m['amount']);
        }
      }

      for (final raw in allSupplierTx) {
        final m = Map<String, dynamic>.from(raw as Map);
        final note = (m['note'] ?? '').toString();
        if (!note.startsWith('Payment Out #')) continue;
        final purchaseIds = (m['purchase_ids'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const <int>[];
        final purchaseId =
            (m['purchase_id'] is num) ? (m['purchase_id'] as num).toInt() : 0;
        final linkedIds = <int>[
          ...purchaseIds,
          if (purchaseId > 0) purchaseId,
        ];
        if (linkedIds.isNotEmpty) {
          for (final id in linkedIds) {
            final billNo = purchaseIdToBillNo[id] ?? 0;
            if (billNo <= 0) continue;
            paymentOutBillNos.add(billNo);
            paymentOutTotals[billNo] =
                (paymentOutTotals[billNo] ?? 0) + _toDouble(m['amount']);
          }
        } else {
          final billNo = _parseBillNoFromNote(note, 'Payment Out #');
          if (billNo <= 0) continue;
          paymentOutBillNos.add(billNo);
          paymentOutTotals[billNo] =
              (paymentOutTotals[billNo] ?? 0) + _toDouble(m['amount']);
        }
      }

      for (final raw in sales) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _toInt(m['id']);
        final number = _safeBillNo(m, 'bill_number');
        final date =
            DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now();
        final sortDate = _serverSortDate(
          createdAt: (m['created_at'] ?? '').toString(),
          updatedAt: (m['updated_at'] ?? '').toString(),
          date: (m['date'] ?? '').toString(),
          id: id,
        );
        final party = ((m['party_name'] ?? '').toString().trim().isEmpty)
            ? 'Walk-in Sale'
            : (m['party_name'] ?? '').toString();
        final total = _billTotal(m);
        final mode = (m['payment_mode'] ?? 'unpaid').toString();
        final paid = _toDouble(m['received_amount'] ?? m['paid_amount']);
        final balance = _toDouble(m['balance_due']);
        final status = _paymentStatus(
          total: total,
          paid: paid,
          balance: balance,
        );

        if (paid > 0 && !paymentInBillNos.contains(number)) {
          mapped.add(
            _BillEntry(
              id: id,
              type: 'payment_in',
              partyName: party,
              label: 'Payment In #$number',
              billNumber: number,
              date: date.add(const Duration(seconds: 1)),
              sortDate: sortDate.add(const Duration(seconds: 1)),
              sortId: id,
              amount: paid,
              paymentMode: mode == 'card' ? 'card' : 'cash',
              paymentStatusLabel: mode == 'card' ? 'Card' : 'Cash',
              statusColor: Colors.black87,
            ),
          );
        }

        mapped.add(
          _BillEntry(
            id: id,
            type: 'sale',
            partyName: party,
            label: 'Sale Bill #$number',
            billNumber: number,
            date: date,
            sortDate: sortDate,
            sortId: id,
            amount: total,
            paymentMode: mode,
            paymentStatusLabel: status['label'] as String,
            statusColor: status['color'] as Color,
          ),
        );
      }

      for (final raw in purchases) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _toInt(m['id']);
        final number = _safeBillNo(m, 'purchase_number');
        final date =
            DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now();
        final sortDate = _serverSortDate(
          createdAt: (m['created_at'] ?? '').toString(),
          updatedAt: (m['updated_at'] ?? '').toString(),
          date: (m['date'] ?? '').toString(),
          id: id,
        );
        final party = ((m['party_name'] ?? '').toString().trim().isEmpty)
            ? 'Walk-in Purchase'
            : (m['party_name'] ?? '').toString();
        final total = _billTotal(m);
        final mode = (m['payment_mode'] ?? 'unpaid').toString();
        final paid = _toDouble(m['paid_amount'] ?? m['received_amount']);
        final balance = _toDouble(m['balance_due']);
        final status = _paymentStatus(
          total: total,
          paid: paid,
          balance: balance,
        );

        if (paid > 0 && !paymentOutBillNos.contains(number)) {
          mapped.add(
            _BillEntry(
              id: id,
              type: 'payment_out',
              partyName: party,
              label: 'Payment Out #$number',
              billNumber: number,
              date: date.add(const Duration(seconds: 1)),
              sortDate: sortDate.add(const Duration(seconds: 1)),
              sortId: id,
              amount: paid,
              paymentMode: mode == 'card' ? 'card' : 'cash',
              paymentStatusLabel: mode == 'card' ? 'Card' : 'Cash',
              statusColor: Colors.black87,
            ),
          );
        }

        mapped.add(
          _BillEntry(
            id: id,
            type: 'purchase',
            partyName: party,
            label: 'Purchase #$number',
            billNumber: number,
            date: date,
            sortDate: sortDate,
            sortId: id,
            amount: total,
            paymentMode: mode,
            paymentStatusLabel: status['label'] as String,
            statusColor: status['color'] as Color,
          ),
        );
      }

      for (final raw in expenses) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _toInt(m['id']);
        final number = _safeBillNo(m, 'expense_number');
        final date =
            DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now();
        final sortDate = _serverSortDate(
          createdAt: (m['created_at'] ?? '').toString(),
          updatedAt: (m['updated_at'] ?? '').toString(),
          date: (m['date'] ?? '').toString(),
          id: id,
        );
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
            sortDate: sortDate,
            sortId: id,
            amount: amount,
            paymentMode: ((m['payment_mode'] ?? 'cash').toString() == 'card')
                ? 'card'
                : 'cash',
            paymentStatusLabel: '',
            statusColor: Colors.black87,
            extraInfo: info.isEmpty ? null : info,
          ),
        );
      }

      for (final raw in saleReturns) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _toInt(m['id']);
        final number = _toInt(m['return_number']);
        final date =
            DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now();
        final sortDate = _serverSortDate(
          createdAt: (m['created_at'] ?? '').toString(),
          updatedAt: (m['updated_at'] ?? '').toString(),
          date: (m['date'] ?? '').toString(),
          id: id,
        );
        final customerId = _toInt(m['customer_id']);
        final party = customerNameById[customerId] ??
            (((m['note'] ?? '').toString().trim().isEmpty)
                ? 'Customer'
                : (m['note'] ?? '').toString());
        final total = _toDouble(m['total_amount']);
        final mode = (m['settlement_mode'] ?? '').toString();

        mapped.add(
          _BillEntry(
            id: id,
            type: 'sale_return',
            partyName: party,
            label: 'Sale Return #$number',
            billNumber: number,
            date: date,
            sortDate: sortDate,
            sortId: id,
            amount: total,
            paymentMode: mode,
            paymentStatusLabel:
                mode == 'credit_party' ? 'Credit to Party' : 'Refund',
            statusColor: const Color(0xFFA88E1F),
          ),
        );
      }

      for (final raw in purchaseReturns) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _toInt(m['id']);
        final number = _toInt(m['return_number']);
        final date =
            DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now();
        final sortDate = _serverSortDate(
          createdAt: (m['created_at'] ?? '').toString(),
          updatedAt: (m['updated_at'] ?? '').toString(),
          date: (m['date'] ?? '').toString(),
          id: id,
        );
        final supplierId = _toInt(m['supplier_id']);
        final party = supplierNameById[supplierId] ??
            (((m['note'] ?? '').toString().trim().isEmpty)
                ? 'Supplier'
                : (m['note'] ?? '').toString());
        final total = _toDouble(m['total_amount']);
        final mode = (m['settlement_mode'] ?? '').toString();

        mapped.add(
          _BillEntry(
            id: id,
            type: 'purchase_return',
            partyName: party,
            label: 'Purchase Return #$number',
            billNumber: number,
            date: date,
            sortDate: sortDate,
            sortId: id,
            amount: total,
            paymentMode: mode,
            paymentStatusLabel:
                mode == 'credit_party' ? 'Credit from Supplier' : 'Refund',
            statusColor: const Color(0xFFA88E1F),
          ),
        );
      }

      final paymentNoRegex = RegExp('#(\\d+)');

      for (final raw in allCustomerTx) {
        final m = Map<String, dynamic>.from(raw as Map);
        final note = (m['note'] ?? '').toString();
        if (!note.startsWith('Payment In #')) continue;
        final nRaw = m['payment_number'];
        final parsedNo = paymentNoRegex.firstMatch(note);
        final n = (nRaw is num)
            ? nRaw.toInt()
            : int.tryParse(parsedNo?.group(1) ?? '') ?? 0;
        final customerId = _toInt(m['customer_id']);
        final date = _serverSortDate(
          createdAt: (m['created_at'] ?? '').toString(),
          updatedAt: (m['updated_at'] ?? '').toString(),
          date: (m['date'] ?? '').toString(),
          id: _toInt(m['id']),
        );
        mapped.add(
          _BillEntry(
            id: _toInt(m['id']),
            type: 'payment_in',
            partyName: customerNameById[customerId] ?? 'Customer',
            label: n > 0 ? 'Payment In #$n' : 'Payment In',
            billNumber: n,
            date: date,
            sortDate: date,
            sortId: _toInt(m['id']),
            amount: _toDouble(m['amount']),
            paymentMode: note.toLowerCase().contains('card') ? 'card' : 'cash',
            paymentStatusLabel:
                note.toLowerCase().contains('card') ? 'Card' : 'Cash',
            statusColor: Colors.black87,
          ),
        );
      }

      for (final raw in allSupplierTx) {
        final m = Map<String, dynamic>.from(raw as Map);
        final note = (m['note'] ?? '').toString();
        if (!note.startsWith('Payment Out #')) continue;
        final nRaw = m['payment_number'];
        final parsedNo = paymentNoRegex.firstMatch(note);
        final n = (nRaw is num)
            ? nRaw.toInt()
            : int.tryParse(parsedNo?.group(1) ?? '') ?? 0;
        final supplierId = _toInt(m['supplier_id']);
        final date = _serverSortDate(
          createdAt: (m['created_at'] ?? '').toString(),
          updatedAt: (m['updated_at'] ?? '').toString(),
          date: (m['date'] ?? '').toString(),
          id: _toInt(m['id']),
        );
        mapped.add(
          _BillEntry(
            id: _toInt(m['id']),
            type: 'payment_out',
            partyName: supplierNameById[supplierId] ?? 'Supplier',
            label: n > 0 ? 'Payment Out #$n' : 'Payment Out',
            billNumber: n,
            date: date,
            sortDate: date,
            sortId: _toInt(m['id']),
            amount: _toDouble(m['amount']),
            paymentMode: note.toLowerCase().contains('card') ? 'card' : 'cash',
            paymentStatusLabel:
                note.toLowerCase().contains('card') ? 'Card' : 'Cash',
            statusColor: Colors.black87,
          ),
        );
      }

      mapped.sort((a, b) {
        final dateCmp = b.sortDate.compareTo(a.sortDate);
        if (dateCmp != 0) return dateCmp;
        return b.sortId.compareTo(a.sortId);
      });

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
      AppEvents.notifyPartiesChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e.toString();
      final isNetwork = msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('Connection refused') ||
          msg.contains('ClientException');
      if (!isNetwork) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh bills: $e')),
        );
      }
    }
  }

  List<_BillEntry> get _filtered {
    Iterable<_BillEntry> rows;
    if (_tab == 'sale') {
      rows = _entries.where((e) =>
          e.type == 'sale' ||
          e.type == 'payment_in' ||
          e.type == 'sale_return');
    } else if (_tab == 'purchase') {
      rows = _entries.where((e) =>
          e.type == 'purchase' ||
          e.type == 'payment_out' ||
          e.type == 'purchase_return');
    } else {
      rows = _entries.where((e) => e.type == 'expense');
    }

    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      final list = rows.toList();
      list.sort((a, b) {
        final dateCmp = b.sortDate.compareTo(a.sortDate);
        if (dateCmp != 0) return dateCmp;
        return b.sortId.compareTo(a.sortId);
      });
      return list;
    }

    final filtered = rows.where((e) {
      return e.partyName.toLowerCase().contains(q) ||
          e.label.toLowerCase().contains(q) ||
          e.billNumber.toString().contains(q) ||
          (e.extraInfo ?? '').toLowerCase().contains(q);
    }).toList();
    filtered.sort((a, b) {
      final dateCmp = b.sortDate.compareTo(a.sortDate);
      if (dateCmp != 0) return dateCmp;
      return b.sortId.compareTo(a.sortId);
    });
    return filtered;
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

  double get _todayInCash => _entries
      .where((e) =>
          e.type == 'payment_in' && e.paymentMode != 'card' && _isToday(e.date))
      .fold(0, (s, e) => s + e.amount);

  double get _todayOutCash => _entries
      .where((e) =>
          (e.type == 'payment_out' || e.type == 'expense') &&
          e.paymentMode != 'card' &&
          _isToday(e.date))
      .fold(0, (s, e) => s + e.amount);

  double get _todayInBank => _entries
      .where((e) =>
          e.type == 'payment_in' && e.paymentMode == 'card' && _isToday(e.date))
      .fold(0, (s, e) => s + e.amount);

  double get _todayOutBank => _entries
      .where((e) =>
          (e.type == 'payment_out' || e.type == 'expense') &&
          e.paymentMode == 'card' &&
          _isToday(e.date))
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

  Future<void> _openReturnActions(_BillEntry entry) async {
    final isSaleReturn = entry.type == 'sale_return';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Return'),
        content: Text(
          'Soft delete ${isSaleReturn ? 'Sale Return' : 'Purchase Return'} #${entry.billNumber}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      if (isSaleReturn) {
        await Api.deleteSaleReturn(entry.id);
      } else {
        await Api.deletePurchaseReturn(entry.id);
      }
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  void _openCashbook() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashbookScreen(
          businessId: _activeBusinessId ?? 0,
          businessName: _businessName,
          title: 'Cashbook',
          reportButtonText: 'VIEW CASHBOOK REPORT',
          modeFilter: 'cash',
        ),
      ),
    );
  }

  void _openBankbook() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashbookScreen(
          businessId: _activeBusinessId ?? 0,
          businessName: _businessName,
          title: 'Bank Book',
          reportButtonText: 'VIEW BANK BOOK REPORT',
          modeFilter: 'card',
        ),
      ),
    );
  }

  Future<void> _openMoreSheet() async {
    final nextReturnNo = _nextNoFromPrefix(
      _tab == 'purchase' ? 'Purchase Return' : 'Sale Return',
    );
    final nextPaymentNo = _nextNoFromPrefix(
      _tab == 'purchase' ? 'Payment Out' : 'Payment In',
    );

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 22 + bottomInset),
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
                      onTap: () {
                        Navigator.pop(context);
                        if (_tab == 'purchase') {
                          _openPurchase();
                        } else {
                          _openSale();
                        }
                      },
                    ),
                    _MoreAction(
                      icon: Icons.assignment_return_outlined,
                      label: _tab == 'purchase'
                          ? 'Purchase Return'
                          : 'Sale Return',
                      bg: const Color(0xFFF9F6DE),
                      fg: const Color(0xFFA88E1F),
                      onTap: () async {
                        Navigator.pop(context);
                        final ok = await Navigator.push<bool>(
                          this.context,
                          MaterialPageRoute(
                            builder: (_) => AddBillReturnScreen(
                              isPurchase: _tab == 'purchase',
                              returnNumber:
                                  nextReturnNo <= 0 ? 1 : nextReturnNo,
                            ),
                          ),
                        );
                        if (ok == true) {
                          _loadAll();
                        }
                      },
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
                      onTap: () async {
                        Navigator.pop(context);
                        final ok = await Navigator.push<bool>(
                          this.context,
                          MaterialPageRoute(
                            builder: (_) => AddBillPaymentScreen(
                              isPurchase: _tab == 'purchase',
                              paymentNumber:
                                  nextPaymentNo <= 0 ? 1 : nextPaymentNo,
                            ),
                          ),
                        );
                        if (ok == true) {
                          _loadAll();
                        }
                      },
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
                              ? 'Purchase, Payment Out, Purchase Return'
                              : 'Sale, Payment In, Sale Return',
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    final canViewSale = AccessControl.canView(_user, 'sale');
    final canViewPurchase = AccessControl.canView(_user, 'purchase');
    final canViewExpense = AccessControl.canView(_user, 'expense');
    final canAddSale = AccessControl.canAdd(_user, 'sale') &&
        AccessControl.canAdd(_user, 'bills');
    final canAddPurchase = AccessControl.canAdd(_user, 'purchase') &&
        AccessControl.canAdd(_user, 'bills');
    final canAddExpense = AccessControl.canAdd(_user, 'expense') &&
        AccessControl.canAdd(_user, 'bills');

    final visibleTabs = <String>[
      if (canViewSale) 'sale',
      if (canViewPurchase) 'purchase',
      if (canViewExpense) 'expense',
    ];
    if (visibleTabs.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No bills access assigned for this user.')),
      );
    }
    if (!visibleTabs.contains(_tab)) {
      _tab = visibleTabs.first;
    }

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
                    const AppBrandLogo(size: 22, textSize: 9, borderRadius: 6),
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
                    const Spacer(),
                    const SyncStatusChip(onDark: true, compact: true),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 60,
                  child: Row(
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
                      Expanded(
                        child: _reportsCard(
                          onTap: () {
                            Navigator.push(
                              context,
                              AppRoutes.onGenerateRoute(
                                const RouteSettings(
                                  name: AppRoutes.reports,
                                  arguments: {'initialTab': 'Bills'},
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _cashStat(
                              value: 'AED ${_todayInCash.toStringAsFixed(0)}',
                              label: "Cash book In",
                              valueColor: const Color(0xFF12965B),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 32,
                            color: const Color(0xFFE6EAF0),
                          ),
                          Expanded(
                            child: _cashStat(
                              value: 'AED ${_todayOutCash.toStringAsFixed(0)}',
                              label: "Cash book Out",
                              valueColor: const Color(0xFFC6284D),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _miniBookButton('Cash Book', _openCashbook),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _cashStat(
                              value: 'AED ${_todayInBank.toStringAsFixed(0)}',
                              label: "Bank book In",
                              valueColor: const Color(0xFF12965B),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 32,
                            color: const Color(0xFFE6EAF0),
                          ),
                          Expanded(
                            child: _cashStat(
                              value: 'AED ${_todayOutBank.toStringAsFixed(0)}',
                              label: "Bank book Out",
                              valueColor: const Color(0xFFC6284D),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _miniBookButton('Bank Book', _openBankbook),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (canViewSale) _billTab('sale', 'Sale'),
                    if (canViewPurchase) _billTab('purchase', 'Purchase'),
                    if (canViewExpense) _billTab('expense', 'Expense'),
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
                  child: RefreshIndicator(
                    onRefresh: _loadAll,
                    child: _loading
                        ? ListView(
                            children: const [
                              SizedBox(height: 200),
                              Center(child: CircularProgressIndicator()),
                            ],
                          )
                        : _filtered.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 120),
                                  Center(
                                    child: Text(
                                      _tab == 'sale'
                                          ? 'No sale bills yet'
                                          : _tab == 'purchase'
                                              ? 'No purchase bills yet'
                                              : 'No expenses yet',
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                itemCount: _filtered.length,
                                padding: const EdgeInsets.only(bottom: 90),
                                itemBuilder: (context, index) {
                                  final e = _filtered[index];
                                  return InkWell(
                                    onTap: e.type == 'expense'
                                        ? () => _openExpenseDetails(e)
                                        : (e.type == 'sale_return' ||
                                                e.type == 'purchase_return')
                                            ? () => _openReturnActions(e)
                                            : (e.type == 'payment_in' ||
                                                    e.type == 'payment_out')
                                                ? () async {
                                                    final updated =
                                                        await Navigator.push<
                                                            bool>(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            PaymentDetailScreen(
                                                          paymentId: e.id,
                                                          paymentNumber:
                                                              e.billNumber,
                                                          isPurchase: e.type ==
                                                              'payment_out',
                                                          partyName:
                                                              e.partyName,
                                                          amount: e.amount,
                                                          paymentMode:
                                                              e.paymentMode,
                                                          date: e.date,
                                                        ),
                                                      ),
                                                    );
                                                    if (updated == true) {
                                                      _loadAll();
                                                    }
                                                  }
                                                : (e.type == 'sale' ||
                                                        e.type == 'purchase')
                                                    ? () async {
                                                        final updated =
                                                            await Navigator
                                                                .push<bool>(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                BillDetailScreen(
                                                              billId: e.id,
                                                              billNumber:
                                                                  e.billNumber,
                                                              isPurchase: e
                                                                      .type ==
                                                                  'purchase',
                                                            ),
                                                          ),
                                                        );
                                                        if (updated == true) {
                                                          _loadAll();
                                                        }
                                                      }
                                                    : null,
                                    child: _entryTile(e),
                                  );
                                },
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
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'MORE',
                        style: TextStyle(
                          color: Color(0xFF1D2A8D),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Payment & Return',
                        style:
                            TextStyle(color: Color(0xFF1D2A8D), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _tab == 'sale'
                      ? (canAddSale ? _openSale : null)
                      : _tab == 'purchase'
                          ? (canAddPurchase ? _openPurchase : null)
                          : (canAddExpense ? _openExpense : null),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D2A8D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
      case 'sale_return':
      case 'purchase_return':
        icon = Icons.assignment_return_outlined;
        bg = const Color(0xFFF9F6DE);
        fg = const Color(0xFFA88E1F);
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
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: bg,
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.partyName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    e.label,
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 11.5),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${e.date.day.toString().padLeft(2, '0')} ${_month(e.date.month)} ${e.date.year.toString().substring(2)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 11.5),
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
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 6),
              if (e.paymentStatusLabel.isNotEmpty)
                Text(
                  e.paymentStatusLabel,
                  style: TextStyle(
                      color: e.statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF6A7280), fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _reportsCard({required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'View Reports',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFF0B4F9E),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 2),
            Icon(Icons.chevron_right, color: Color(0xFF0B4F9E), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _miniBookButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: 82,
      height: 28,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD8E3F1)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF0B4F9E),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cashStat({
    required String value,
    required String label,
    required Color valueColor,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF6A7280), fontSize: 10.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _MoreAction extends StatelessWidget {
  const _MoreAction({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            CircleAvatar(
                radius: 26, backgroundColor: bg, child: Icon(icon, color: fg)),
            const SizedBox(height: 8),
            Text(label),
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
