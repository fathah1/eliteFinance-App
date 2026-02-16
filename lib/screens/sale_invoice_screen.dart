import 'dart:io';
import 'dart:typed_data';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class SaleInvoiceScreen extends StatefulWidget {
  const SaleInvoiceScreen({super.key, required this.sale});

  final Map<String, dynamic> sale;

  @override
  State<SaleInvoiceScreen> createState() => _SaleInvoiceScreenState();
}

class _SaleInvoiceScreenState extends State<SaleInvoiceScreen> {
  String _mode = 'pdf'; // pdf | thermal
  bool _busy = false;
  final BlueThermalPrinter _thermal = BlueThermalPrinter.instance;

  String get _invoiceTitle =>
      'Invoice #${(widget.sale['bill_number'] ?? '').toString()}';

  List<Map<String, dynamic>> get _items {
    final raw = widget.sale['items'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  double _n(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _dateText() => (widget.sale['date'] ?? '').toString();

  Future<Uint8List> _buildPdfBytes() async {
    final doc = pw.Document();
    final partyName =
        ((widget.sale['party_name'] ?? '').toString().trim().isEmpty)
            ? 'Walk-in Sale'
            : (widget.sale['party_name'] ?? '').toString();
    final partyPhone = (widget.sale['party_phone'] ?? '').toString();
    final subtotal = _n(widget.sale['subtotal']);
    final addCharges = _n(widget.sale['additional_charges_total']);
    final discount = _n(widget.sale['discount_amount']);
    final total = _n(widget.sale['total_amount']);
    final received = _n(widget.sale['received_amount']);
    final balance = _n(widget.sale['balance_due']);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Container(
          padding: const pw.EdgeInsets.all(18),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('INVOICE',
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_invoiceTitle,
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Text('Invoice Date: ${_dateText()}'),
              pw.SizedBox(height: 10),
              pw.Text('Bill To: $partyName'),
              if (partyPhone.isNotEmpty) pw.Text('Phone: $partyPhone'),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _cell('Item'),
                      _cell('Qty'),
                      _cell('Rate'),
                      _cell('Amount'),
                    ],
                  ),
                  ..._items.map(
                    (it) => pw.TableRow(
                      children: [
                        _cell((it['name'] ?? '').toString()),
                        _cell((it['qty'] ?? '').toString()),
                        _cell('AED ${_n(it['price']).toStringAsFixed(0)}'),
                        _cell('AED ${_n(it['line_total']).toStringAsFixed(0)}'),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              _sumRow('Sub-total', subtotal),
              _sumRow('Additional Charges', addCharges),
              _sumRow('Discount', -discount),
              pw.Divider(),
              _sumRow('Total', total, bold: true),
              _sumRow('Received', received),
              _sumRow('Balance Due', balance),
              pw.Spacer(),
              pw.Center(
                child: pw.Text('~ THIS IS A DIGITALLY CREATED INVOICE ~'),
              ),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _cell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 10)),
      );

  pw.Widget _sumRow(String label, double amount, {bool bold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(
          'AED ${amount.toStringAsFixed(0)}',
          style: pw.TextStyle(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      ],
    );
  }

  Future<File> _writePdf() async {
    final bytes = await _buildPdfBytes();
    final dir = await getApplicationDocumentsDirectory();
    final billNo = (widget.sale['bill_number'] ?? 'invoice').toString();
    final file = File('${dir.path}/invoice_$billNo.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _downloadPdf() async {
    setState(() => _busy = true);
    try {
      final file = await _writePdf();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice saved: ${file.path}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareWhatsapp() async {
    setState(() => _busy = true);
    try {
      final file = await _writePdf();
      final billNo = (widget.sale['bill_number'] ?? '').toString();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Invoice #$billNo',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printThermal() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    if (!scan.isGranted || !connect.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth permission required')),
      );
      return;
    }

    final devices = await _thermal.getBondedDevices();
    if (!mounted) return;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No paired thermal printer found')),
      );
      return;
    }

    final selected = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: devices
              .map(
                (d) => ListTile(
                  title: Text(d.name ?? 'Unknown'),
                  subtitle: Text(d.address ?? ''),
                  onTap: () => Navigator.pop(context, d),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected == null) return;

    setState(() => _busy = true);
    try {
      await _thermal.connect(selected);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final text = _thermalText();
      await _thermal.write(text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice sent to thermal printer')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _thermalText() {
    final b = StringBuffer();
    final partyName =
        ((widget.sale['party_name'] ?? '').toString().trim().isEmpty)
            ? 'Walk-in Sale'
            : (widget.sale['party_name'] ?? '').toString();
    b.writeln('       SALE INVOICE');
    b.writeln('Invoice No: ${(widget.sale['bill_number'] ?? '')}');
    b.writeln('Date: ${_dateText()}');
    b.writeln('Party: $partyName');
    b.writeln('-------------------------------');
    for (final it in _items) {
      b.writeln((it['name'] ?? '').toString());
      b.writeln(
          '${(it['qty'] ?? '').toString()} x AED ${_n(it['price']).toStringAsFixed(0)}   AED ${_n(it['line_total']).toStringAsFixed(0)}');
    }
    b.writeln('-------------------------------');
    b.writeln(
        'Total: AED ${_n(widget.sale['total_amount']).toStringAsFixed(0)}');
    b.writeln(
        'Received: AED ${_n(widget.sale['received_amount']).toStringAsFixed(0)}');
    b.writeln(
        'Balance: AED ${_n(widget.sale['balance_due']).toStringAsFixed(0)}');
    b.writeln('-------------------------------');
    b.writeln('Thank you');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFEF),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Text(_invoiceTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(14),
                child: _mode == 'pdf' ? _pdfPreview() : _thermalPreview(),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(child: _modeBtn('pdf', 'PDF')),
                const SizedBox(width: 10),
                Expanded(child: _modeBtn('thermal', 'Thermal')),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                if (_mode == 'thermal')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _printThermal,
                      icon: const Icon(Icons.print),
                      label: const Text('Print'),
                    ),
                  ),
                if (_mode == 'thermal') const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _downloadPdf,
                    icon: const Icon(Icons.download),
                    label: const Text('Download Invoice'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _shareWhatsapp,
                    icon: const Icon(Icons.share),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, 'create_new'),
                      child: const Text('CREATE NEW'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, 'done'),
                      child: const Text('DONE'),
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

  Widget _modeBtn(String value, String text) {
    final selected = _mode == value;
    return OutlinedButton(
      onPressed: () => setState(() => _mode = value),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFFEAF2FF) : Colors.white,
      ),
      child: Text(text),
    );
  }

  Widget _pdfPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Invoice No.${widget.sale['bill_number']}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Invoice Date: ${_dateText()}'),
        const Divider(height: 24),
        ..._items.map(
          (it) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text((it['name'] ?? '').toString())),
                Text(
                    '${(it['qty'] ?? '').toString()} x AED ${_n(it['price']).toStringAsFixed(0)}'),
                const SizedBox(width: 12),
                Text('AED ${_n(it['line_total']).toStringAsFixed(0)}'),
              ],
            ),
          ),
        ),
        const Divider(height: 24),
        _previewSum('Sub-total', _n(widget.sale['subtotal'])),
        _previewSum(
            'Additional Charges', _n(widget.sale['additional_charges_total'])),
        _previewSum('Discount', -_n(widget.sale['discount_amount'])),
        const SizedBox(height: 8),
        _previewSum('Total amount', _n(widget.sale['total_amount']),
            bold: true),
      ],
    );
  }

  Widget _thermalPreview() {
    return Center(
      child: Container(
        width: 230,
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: Text(
          _thermalText(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ),
    );
  }

  Widget _previewSum(String label, double value, {bool bold = false}) {
    final style = TextStyle(
      fontSize: 16,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('AED ${value.toStringAsFixed(0)}', style: style),
        ],
      ),
    );
  }
}
