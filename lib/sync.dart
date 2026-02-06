import 'api.dart';
import 'db.dart';

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  bool _running = false;

  Future<void> syncAll() async {
    if (_running) return;
    _running = true;
    try {
      await _pushCustomers();
      await _pushTransactions();
      await _pullCustomers();
      await _pullTransactions();
    } finally {
      _running = false;
    }
  }

  Future<void> _pushCustomers() async {
    final db = Db.instance;
    final customers = await db.listCustomersWithBalance();
    for (final c in customers) {
      if ((c['server_id'] as int?) != null) continue;
      try {
        final created = await Api.createCustomer(
          name: (c['name'] ?? '').toString(),
          phone: (c['phone'] ?? '').toString().isEmpty
              ? null
              : (c['phone'] ?? '').toString(),
          openingBalance:
              (c['opening_balance'] as num?)?.toDouble() ?? 0,
        );
        if (created['id'] != null) {
          await db.updateCustomerServerInfo(
            id: c['id'] as int,
            serverId: created['id'] as int,
          );
        }
      } catch (_) {
        // offline or server error
      }
    }
  }

  Future<void> _pushTransactions() async {
    final db = Db.instance;
    final txs = await db.listUnsyncedTransactions();
    if (txs.isEmpty) return;

    final customers = await db.listCustomersWithBalance();
    for (final t in txs) {
      final localCustomerId = t['customer_id'] as int;
      final customer = customers.firstWhere(
        (c) => c['id'] == localCustomerId,
        orElse: () => {},
      );
      final serverCustomerId = customer['server_id'] as int?;
      if (serverCustomerId == null) continue;

      try {
        Map<String, dynamic> saved;
        if (t['server_id'] != null) {
          saved = await Api.updateTransaction(
            transactionId: t['server_id'] as int,
            amount: (t['amount'] as num).toDouble(),
            type: (t['type'] ?? 'CREDIT').toString(),
            note: (t['note'] ?? '').toString(),
            createdAt: (t['created_at'] ?? '').toString(),
          );
        } else {
          saved = await Api.createTransaction(
            customerId: serverCustomerId,
            amount: (t['amount'] as num).toDouble(),
            type: (t['type'] ?? 'CREDIT').toString(),
            note: (t['note'] ?? '').toString(),
            createdAt: (t['created_at'] ?? '').toString(),
          );
        }

        if (saved['id'] != null) {
          await db.updateTransactionServerInfo(
            id: t['id'] as int,
            serverId: saved['id'] as int,
          );
        }
      } catch (_) {
        // offline or server error
      }
    }
  }

  Future<void> _pullCustomers() async {
    try {
      final data = await Api.getCustomers();
      await Db.instance.upsertCustomersFromServer(
          data.cast<Map<String, dynamic>>());
    } catch (_) {
      // ignore
    }
  }

  Future<void> _pullTransactions() async {
    try {
      final data = await Api.getAllTransactions();
      await Db.instance.upsertTransactionsFromServer(
          data.cast<Map<String, dynamic>>());
    } catch (_) {
      // ignore
    }
  }
}
