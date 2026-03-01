import 'dart:async';

import 'db.dart';
import 'offline_sync_service.dart';

class OfflineQueue {
  OfflineQueue._();

  static Future<void> push({
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    await Db.instance.enqueuePendingOp(action: action, payload: payload);
    await OfflineSyncService.instance.refreshStatus();
    unawaited(OfflineSyncService.instance.syncPendingNow());
  }
}
