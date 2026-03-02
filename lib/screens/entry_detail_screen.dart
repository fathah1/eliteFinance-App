import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';

class EntryDetailScreen extends StatelessWidget {
  final String title;
  final Map<String, dynamic> entry;
  final double runningBalance;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String? attachmentUrl;
  final String? partyImageUrl;

  const EntryDetailScreen({
    super.key,
    required this.title,
    required this.entry,
    required this.runningBalance,
    required this.onEdit,
    required this.onDelete,
    this.attachmentUrl,
    this.partyImageUrl,
  });

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('dd MMM yyyy • hh:mm a').format(dt);
  }

  Color _amountColor(String type) {
    return type == 'CREDIT' ? const Color(0xFFC62828) : const Color(0xFF1B8F3C);
  }

  Color _balanceColor(double value) {
    if (value > 0) return const Color(0xFFC62828);
    if (value < 0) return const Color(0xFF1B8F3C);
    return Colors.black87;
  }

  void _openImagePreview(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Attachment'),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text(
                  'Image unavailable',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareEntry(BuildContext context) async {
    final type = (entry['type'] ?? '').toString().toUpperCase();
    final action = type == 'CREDIT' ? 'You gave' : 'You got';
    final amount = _asDouble(entry['amount']).toStringAsFixed(0);
    final balance = runningBalance.abs().toStringAsFixed(0);
    final createdAt = _formatDate((entry['created_at'] ?? '').toString());
    final note = (entry['note'] ?? '').toString().trim();

    final message = StringBuffer()
      ..writeln('$title')
      ..writeln('$action AED $amount')
      ..writeln('Running balance: AED $balance')
      ..writeln('Date: $createdAt');
    if (note.isNotEmpty) {
      message.writeln('Note: $note');
    }

    final resolvedAttachment = Api.resolveMediaUrl(
      attachmentUrl ??
          entry['attachment_url'] ??
          entry['attachment_path'] ??
          entry['attachment'],
    );
    if (resolvedAttachment != null && resolvedAttachment.isNotEmpty) {
      message.writeln('Attachment: $resolvedAttachment');
    }
    await Share.share(message.toString());
  }

  @override
  Widget build(BuildContext context) {
    const brandBlue = Color(0xFF0B4F9E);
    final amountValue = _asDouble(entry['amount']);
    final amount = amountValue.toStringAsFixed(0);
    final type = (entry['type'] ?? '').toString();
    final date = _formatDate((entry['created_at'] ?? '').toString());
    final amountColor = _amountColor(type);
    final balanceColor = _balanceColor(runningBalance);
    final typeText = type == 'CREDIT' ? 'You gave' : 'You got';
    final resolvedAttachmentUrl = Api.resolveMediaUrl(
      attachmentUrl ??
          entry['attachment_url'] ??
          entry['attachment_path'] ??
          entry['attachment'],
    );
    final resolvedPartyImage = Api.resolveMediaUrl(
      partyImageUrl ??
          entry['customer_photo_url'] ??
          entry['supplier_photo_url'] ??
          entry['party_photo_url'] ??
          entry['photo_url'],
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: const Text('Entry Details'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (resolvedAttachmentUrl != null &&
                      resolvedAttachmentUrl.isNotEmpty)
                    GestureDetector(
                      onTap: () =>
                          _openImagePreview(context, resolvedAttachmentUrl),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Image.network(
                              resolvedAttachmentUrl,
                              fit: BoxFit.cover,
                              height: 180,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                height: 120,
                                child: Center(child: Text('Image unavailable')),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.zoom_in,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tap to zoom',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: const Color(0xFFE8EEF9),
                                backgroundImage: resolvedPartyImage == null
                                    ? null
                                    : NetworkImage(resolvedPartyImage),
                                child: resolvedPartyImage == null
                                    ? Text(
                                        title.isNotEmpty
                                            ? title[0].toUpperCase()
                                            : 'A',
                                        style: const TextStyle(
                                          color: brandBlue,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 24,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      date,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'AED $amount',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: amountColor,
                                    ),
                                  ),
                                  Text(
                                    typeText,
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          if ((entry['note'] ?? '').toString().trim().isNotEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE1E8F5)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Note',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    (entry['note'] ?? '').toString(),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Running Balance',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'AED ${runningBalance.abs().toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: balanceColor,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit, color: brandBlue),
                              label: const Text(
                                'EDIT ENTRY',
                                style: TextStyle(
                                  color: brandBlue,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'DELETE',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _shareEntry(context),
                    icon: const Icon(Icons.share),
                    label: const Text(
                      'SHARE',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
