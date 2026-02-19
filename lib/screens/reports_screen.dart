import 'package:flutter/material.dart';
import 'bills_reports_screen.dart';
import 'customer_transactions_report_screen.dart';
import 'day_wise_report_screen.dart';
import 'inventory_reports_screen.dart';
import 'supplier_transactions_report_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    this.initialTab = 'All',
  });

  final String initialTab;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportItem {
  const _ReportItem({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

class _ReportSection {
  const _ReportSection({
    required this.title,
    required this.category,
    required this.items,
  });

  final String title;
  final String category;
  final List<_ReportItem> items;
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const Color _brandBlue = Color(0xFF0B4F9E);
  String _selected = 'All';

  static const List<String> _tabs = [
    'All',
    'Customer',
    'Bills',
    'VAT',
    'Day-wise',
    'Inventory',
    'Supplier',
  ];

  static const List<_ReportSection> _sections = [
    _ReportSection(
      title: 'Customer Reports',
      category: 'Customer',
      items: [
        _ReportItem(
          title: 'Customer Transactions report',
          subtitle: 'Summary of all customer transactions',
          icon: Icons.description_outlined,
        ),
        _ReportItem(
          title: 'Customer list pdf',
          subtitle: 'List of all Customers',
          icon: Icons.picture_as_pdf_outlined,
        ),
      ],
    ),
    _ReportSection(
      title: 'Bills Reports',
      category: 'Bills',
      items: [
        _ReportItem(
          title: 'Sales Report',
          subtitle: 'Summary of all Sales',
          icon: Icons.description_outlined,
        ),
        _ReportItem(
          title: 'Purchase Report',
          subtitle: 'Summary of all Purchases',
          icon: Icons.description_outlined,
        ),
        _ReportItem(
          title: 'Cashbook Report',
          subtitle: 'Summary of all Cashflows',
          icon: Icons.description_outlined,
        ),
      ],
    ),
    _ReportSection(
      title: 'VAT Reports',
      category: 'VAT',
      items: [
        _ReportItem(
          title: 'VAT Report',
          subtitle: 'Summary of VAT details',
          icon: Icons.request_quote_outlined,
        ),
      ],
    ),
    _ReportSection(
      title: 'Day-wise Reports',
      category: 'Day-wise',
      items: [
        _ReportItem(
          title: 'Sales Day-wise Report',
          subtitle: 'Daily Sales Summary',
          icon: Icons.description_outlined,
        ),
        _ReportItem(
          title: 'Purchase Day-wise Report',
          subtitle: 'Daily Purchases Summary',
          icon: Icons.description_outlined,
        ),
      ],
    ),
    _ReportSection(
      title: 'Inventory Reports',
      category: 'Inventory',
      items: [
        _ReportItem(
          title: 'Stock Summary',
          subtitle: 'Summary of all items',
          icon: Icons.description_outlined,
        ),
        _ReportItem(
          title: 'Low Stock Summary Report',
          subtitle: 'Summary of all low stock items',
          icon: Icons.description_outlined,
        ),
        _ReportItem(
          title: 'Profit & Loss Report',
          subtitle: 'Summary of item level profit & loss',
          icon: Icons.description_outlined,
        ),
      ],
    ),
    _ReportSection(
      title: 'Supplier Reports',
      category: 'Supplier',
      items: [
        _ReportItem(
          title: 'Supplier Transactions report',
          subtitle: 'Summary of all supplier transactions',
          icon: Icons.description_outlined,
        ),
        _ReportItem(
          title: 'Supplier list pdf',
          subtitle: 'List of all Suppliers',
          icon: Icons.picture_as_pdf_outlined,
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (_tabs.contains(widget.initialTab)) {
      _selected = widget.initialTab;
    }
  }

  List<_ReportSection> get _visibleSections {
    if (_selected == 'All') return _sections;
    return _sections.where((s) => s.category == _selected).toList();
  }

  void _openReport(_ReportItem item) {
    if (item.title == 'Customer Transactions report') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CustomerTransactionsReportScreen(),
        ),
      );
      return;
    }
    if (item.title == 'Customer list pdf') {
      exportCustomerListPdfReport(context);
      return;
    }
    if (item.title == 'Supplier Transactions report') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const SupplierTransactionsReportScreen(),
        ),
      );
      return;
    }
    if (item.title == 'Supplier list pdf') {
      exportSupplierListPdfReport(context);
      return;
    }
    if (item.title == 'Sales Report') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const BillsReportScreen(type: BillReportType.sales),
        ),
      );
      return;
    }
    if (item.title == 'Purchase Report') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const BillsReportScreen(type: BillReportType.purchase),
        ),
      );
      return;
    }
    if (item.title == 'Cashbook Report') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const BillsReportScreen(type: BillReportType.cashbook),
        ),
      );
      return;
    }
    if (item.title == 'Sales Day-wise Report') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const DayWiseReportScreen(type: DayWiseReportType.sales),
        ),
      );
      return;
    }
    if (item.title == 'Purchase Day-wise Report') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const DayWiseReportScreen(type: DayWiseReportType.purchase),
        ),
      );
      return;
    }
    if (item.title == 'Stock Summary') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const InventoryReportsScreen(
            type: InventoryReportType.stockSummary,
          ),
        ),
      );
      return;
    }
    if (item.title == 'Low Stock Summary Report') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const InventoryReportsScreen(
            type: InventoryReportType.lowStockSummary,
          ),
        ),
      );
      return;
    }
    if (item.title == 'Profit & Loss Report') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const InventoryReportsScreen(
            type: InventoryReportType.profitLoss,
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ReportUnderDevelopmentScreen(title: item.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(
        title: const Text('View Reports'),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, i) {
                final tab = _tabs[i];
                final selected = tab == _selected;
                return InkWell(
                  onTap: () => setState(() => _selected = tab),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFEAF2FF) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF4A90E2)
                            : const Color(0xFFD8DDE5),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tab,
                      style: TextStyle(
                        color: selected ? _brandBlue : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _tabs.length,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: _visibleSections.length,
              itemBuilder: (_, index) {
                final section = _visibleSections[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDADFE6)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(section.items.length, (i) {
                        final item = section.items[i];
                        return Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(item.icon, color: _brandBlue),
                              title: Text(
                                item.title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                item.subtitle,
                                style: const TextStyle(
                                  color: Color(0xFF7A828F),
                                  fontSize: 14,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 24,
                              ),
                              onTap: () => _openReport(item),
                            ),
                            if (i != section.items.length - 1)
                              const Divider(height: 1),
                          ],
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportUnderDevelopmentScreen extends StatelessWidget {
  const _ReportUnderDevelopmentScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(
        child: Text(
          'Under Development',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
