import 'api.dart';
import 'db.dart';

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  bool _running = false;

  Future<void> syncAll({int? businessId}) async {
    if (_running) return;
    _running = true;
    try {
      await _pushBusinesses();
      if (businessId != null) {
        await _pushCustomers(businessId);
        await _pushTransactions(businessId);
        await _pullCustomers(businessId);
        await _pullTransactions(businessId);
      }
      await _pullBusinesses();
    } finally {
      _running = false;
    }
  }

  Future<void> _pushBusinesses() async {
    final db = Db.instance;
    final businesses = await db.listBusinesses();
    for (final b in businesses) {
      if ((b['server_id'] as int?) != null) continue;
      try {
        final created = await Api.createBusiness(
          name: (b['name'] ?? '').toString(),
        );
        if (created['id'] != null) {
          await db.updateBusinessServerInfo(
            id: b['id'] as int,
            serverId: created['id'] as int,
          );
        }
      } catch (_) {
        // offline or server error
      }
    }
  }

  Future<void> _pullBusinesses() async {
    try {
      final data = await Api.getBusinesses();
      await Db.instance.upsertBusinessesFromServer(
          data.cast<Map<String, dynamic>>());
    } catch (_) {
      // ignore
    }
  }

  Future<void> _pushCustomers(int businessId) async {
    final db = Db.instance;
    final customers = await db.listCustomersWithBalance(businessId: businessId);
    for (final c in customers) {
      if ((c['server_id'] as int?) != null) continue;
      try {
        final bizList = await db.listBusinesses();
        final localBiz = bizList.firstWhere(
          (b) => b['id'] == businessId,
          orElse: () => {},
        );
        final serverBizId = localBiz['server_id'] as int?;
        if (serverBizId == null) continue;

        final created = await Api.createCustomer(
          businessId: serverBizId,
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

  Future<void> _pushTransactions(int businessId) async {
    final db = Db.instance;
    final txs = await db.listUnsyncedTransactions(businessId: businessId);
    if (txs.isEmpty) return;

    final customers = await db.listCustomersWithBalance(businessId: businessId);
    final businesses = await db.listBusinesses();
    final localBiz = businesses.firstWhere(
      (b) => b['id'] == businessId,
      orElse: () => {},
    );
    final serverBizId = localBiz['server_id'] as int?;
    if (serverBizId == null) return;

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
            businessId: serverBizId,
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

  Future<void> _pullCustomers(int businessId) async {
    try {
      final businesses = await Db.instance.listBusinesses();
      final localBiz = businesses.firstWhere(
        (b) => b['id'] == businessId,
        orElse: () => {},
      );
      final serverBizId = localBiz['server_id'] as int?;
      if (serverBizId == null) return;

      final data = await Api.getCustomers(businessId: serverBizId);
      await Db.instance.upsertCustomersFromServer(
          data.cast<Map<String, dynamic>>());
    } catch (_) {
      // ignore
    }
  }

  Future<void> _pullTransactions(int businessId) async {
    try {
      final businesses = await Db.instance.listBusinesses();
      final localBiz = businesses.firstWhere(
        (b) => b['id'] == businessId,
        orElse: () => {},
      );
      final serverBizId = localBiz['server_id'] as int?;
      if (serverBizId == null) return;

      final data = await Api.getAllTransactions(businessId: serverBizId);
      await Db.instance.upsertTransactionsFromServer(
          data.cast<Map<String, dynamic>>());
    } catch (_) {
      // ignore
    }
  }
}
