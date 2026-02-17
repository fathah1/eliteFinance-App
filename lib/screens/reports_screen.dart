import 'package:flutter/material.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

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

  List<_ReportSection> get _visibleSections {
    if (_selected == 'All') return _sections;
    return _sections.where((s) => s.category == _selected).toList();
  }

  void _openReport(_ReportItem item) {
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
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, i) {
                final tab = _tabs[i];
                final selected = tab == _selected;
                return InkWell(
                  onTap: () => setState(() => _selected = tab),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFEAF2FF) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemCount: _tabs.length,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: _visibleSections.length,
              itemBuilder: (_, index) {
                final section = _visibleSections[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDADFE6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 22,
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
                                style: const TextStyle(fontSize: 20),
                              ),
                              subtitle: Text(
                                item.subtitle,
                                style: const TextStyle(
                                  color: Color(0xFF7A828F),
                                  fontSize: 15,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 30,
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
