import 'package:flutter/material.dart';

import '../offline_sync_service.dart';

class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({
    super.key,
    this.onDark = false,
    this.compact = false,
  });

  final bool onDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OfflineSyncStatus>(
      valueListenable: OfflineSyncService.instance.status,
      builder: (_, status, __) {
        final style = _style(status);
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: onDark ? Colors.white.withValues(alpha: 0.18) : style.bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: onDark ? Colors.white30 : style.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                style.icon,
                size: compact ? 12 : 14,
                color: onDark ? Colors.white : style.fg,
              ),
              const SizedBox(width: 4),
              Text(
                style.label,
                style: TextStyle(
                  fontSize: compact ? 10 : 12,
                  fontWeight: FontWeight.w600,
                  color: onDark ? Colors.white : style.fg,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _SyncUi _style(OfflineSyncStatus s) {
    if (!s.isOnline) {
      return const _SyncUi(
        label: 'Offline',
        icon: Icons.cloud_off,
        fg: Color(0xFFC62828),
        bg: Color(0xFFFFEBEE),
        border: Color(0xFFFFCDD2),
      );
    }
    if (s.isSyncing && s.queuedCount > 0) {
      return const _SyncUi(
        label: 'Syncing',
        icon: Icons.sync,
        fg: Color(0xFF0B4F9E),
        bg: Color(0xFFEAF3FF),
        border: Color(0xFFB9D7FF),
      );
    }
    if (s.queuedCount > 0) {
      return _SyncUi(
        label: 'Queued ${s.queuedCount}',
        icon: Icons.schedule,
        fg: const Color(0xFF8A6D1C),
        bg: const Color(0xFFFFF8E1),
        border: const Color(0xFFFFECB3),
      );
    }
    return const _SyncUi(
      label: 'Synced',
      icon: Icons.cloud_done,
      fg: Color(0xFF1B8F3C),
      bg: Color(0xFFEAF9EE),
      border: Color(0xFFC8E6C9),
    );
  }
}

class _SyncUi {
  const _SyncUi({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.border,
  });

  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Color border;
}
