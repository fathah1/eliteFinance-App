import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'db.dart';

class OfflineSyncStatus {
  const OfflineSyncStatus({
    required this.queuedCount,
    required this.isSyncing,
    required this.isOnline,
    this.lastError,
  });

  final int queuedCount;
  final bool isSyncing;
  final bool isOnline;
  final String? lastError;

  OfflineSyncStatus copyWith({
    int? queuedCount,
    bool? isSyncing,
    bool? isOnline,
    String? lastError,
    bool clearError = false,
  }) {
    return OfflineSyncStatus(
      queuedCount: queuedCount ?? this.queuedCount,
      isSyncing: isSyncing ?? this.isSyncing,
      isOnline: isOnline ?? this.isOnline,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  Timer? _timer;
  bool _running = false;
  final ValueNotifier<OfflineSyncStatus> status = ValueNotifier(
    const OfflineSyncStatus(
      queuedCount: 0,
      isSyncing: false,
      isOnline: true,
    ),
  );

  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => syncPendingNow(),
    );
    unawaited(refreshStatus());
    unawaited(syncPendingNow());
  }

  Future<void> syncPendingNow() async {
    if (_running) return;
    _running = true;
    try {
      final queuedBefore = await Db.instance.pendingOpsCount();
      _setStatus(
        status.value.copyWith(
          queuedCount: queuedBefore,
          isSyncing: queuedBefore > 0,
        ),
      );

      final online = await _isOnline();
      if (!online) {
        _setStatus(status.value.copyWith(isOnline: false, isSyncing: false));
        return;
      }
      _setStatus(status.value.copyWith(isOnline: true));

      var token = await Api.getToken();
      if (token == null || token.isEmpty) {
        final restored =
            await Api.trySilentOnlineReloginFromOfflineCredential();
        if (!restored) {
          _setStatus(
            status.value.copyWith(
              isSyncing: false,
              lastError: 'Online re-login required to sync queued data.',
            ),
          );
          await refreshStatus();
          return;
        }
        token = await Api.getToken();
        if (token == null || token.isEmpty) {
          _setStatus(
            status.value.copyWith(
              isSyncing: false,
              lastError: 'Missing auth token for sync.',
            ),
          );
          await refreshStatus();
          return;
        }
      }

      final ops = await Db.instance.listPendingOps(limit: 50);
      for (final op in ops) {
        final id = op['id'] as int;
        final action = (op['action'] ?? '').toString();
        Map<String, dynamic> payload = {};
        try {
          payload = Map<String, dynamic>.from(
            jsonDecode((op['payload'] ?? '{}').toString()) as Map,
          );
        } catch (_) {}

        try {
          debugPrint('Offline sync dispatch: #$id $action');
          await _dispatch(action: action, payload: payload);
          await Db.instance.deletePendingOp(id);
          final queued = await Db.instance.pendingOpsCount();
          _setStatus(
            status.value.copyWith(
              queuedCount: queued,
              isSyncing: queued > 0,
              clearError: true,
            ),
          );
        } catch (e) {
          if (_isInvalidCustomerError(e)) {
            final repaired = await _repairCustomerReference(
              opId: id,
              action: action,
              payload: payload,
            );
            if (repaired) {
              try {
                debugPrint(
                    'Offline sync retry: #$id $action (customer repaired)');
                await _dispatch(action: action, payload: payload);
                await Db.instance.deletePendingOp(id);
                final queued = await Db.instance.pendingOpsCount();
                _setStatus(
                  status.value.copyWith(
                    queuedCount: queued,
                    isSyncing: queued > 0,
                    clearError: true,
                  ),
                );
                continue;
              } catch (retryError) {
                debugPrint(
                    'Offline sync retry failed: #$id $action => $retryError');
                await Db.instance.markPendingOpAttempt(
                  id,
                  error: retryError.toString(),
                );
                _setStatus(
                  status.value.copyWith(
                    lastError: retryError.toString(),
                    isOnline: !_isNetworkError(retryError),
                  ),
                );
                if (_isNetworkError(retryError)) break;
                continue;
              }
            }
          }
          debugPrint('Offline sync failed: #$id $action => $e');
          await Db.instance.markPendingOpAttempt(id, error: e.toString());
          _setStatus(
            status.value.copyWith(
              lastError: e.toString(),
              isOnline: !_isNetworkError(e),
            ),
          );
          if (_isNetworkError(e)) break;
        }
      }
    } finally {
      _running = false;
      await refreshStatus();
    }
  }

  Future<void> refreshStatus() async {
    final queued = await Db.instance.pendingOpsCount();
    bool online = status.value.isOnline;
    try {
      online = await _isOnline();
    } catch (_) {}
    _setStatus(
      status.value.copyWith(
        queuedCount: queued,
        isSyncing: _running && queued > 0,
        isOnline: online,
      ),
    );
  }

  void _setStatus(OfflineSyncStatus next) {
    if (status.value.queuedCount == next.queuedCount &&
        status.value.isSyncing == next.isSyncing &&
        status.value.isOnline == next.isOnline &&
        status.value.lastError == next.lastError) {
      return;
    }
    status.value = next;
  }

  Future<void> _dispatch({
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    switch (action) {
      case 'customer.create':
        final businessId = payload['businessId'] as int;
        final name = (payload['name'] ?? '').toString();
        final phone = payload['phone']?.toString();
        final localIdRaw = payload['localCustomerId'];
        final localId = localIdRaw is num
            ? localIdRaw.toInt()
            : int.tryParse(localIdRaw?.toString() ?? '');

        final existingId = await _findMatchingServerCustomerId(
          businessId: businessId,
          name: name,
          phone: phone,
        );

        int? serverId = existingId;
        if (serverId == null) {
          final created = await Api.createCustomer(
            businessId: businessId,
            name: name,
            phone: phone,
            photoPath: payload['photoPath']?.toString(),
            queueOnFailure: false,
          );
          final serverIdRaw = created['id'];
          serverId = serverIdRaw is num
              ? serverIdRaw.toInt()
              : int.tryParse(serverIdRaw?.toString() ?? '');
        }

        if (localId != null && serverId != null && localId != serverId) {
          await Db.instance
              .remapPendingCustomerId(fromId: localId, toId: serverId);
        }
        return;
      case 'customer.update':
        await Api.updateCustomer(
          customerId: payload['customerId'] as int,
          name: (payload['name'] ?? '').toString(),
          phone: payload['phone']?.toString(),
          photoPath: payload['photoPath']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'customer.delete':
        await Api.deleteCustomer(
          payload['customerId'] as int,
          queueOnFailure: false,
        );
        return;
      case 'supplier.create':
        await Api.createSupplier(
          businessId: payload['businessId'] as int,
          name: (payload['name'] ?? '').toString(),
          phone: payload['phone']?.toString(),
          photoPath: payload['photoPath']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'supplier.update':
        await Api.updateSupplier(
          supplierId: payload['supplierId'] as int,
          name: (payload['name'] ?? '').toString(),
          phone: payload['phone']?.toString(),
          photoPath: payload['photoPath']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'supplier.delete':
        await Api.deleteSupplier(
          payload['supplierId'] as int,
          queueOnFailure: false,
        );
        return;
      case 'transaction.create':
        await Api.createTransaction(
          businessId: payload['businessId'] as int,
          customerId: payload['customerId'] as int,
          amount: (payload['amount'] as num).toDouble(),
          type: (payload['type'] ?? '').toString(),
          note: payload['note']?.toString(),
          createdAt: payload['createdAt']?.toString(),
          attachmentPath: payload['attachmentPath']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'transaction.update':
        await Api.updateTransaction(
          transactionId: payload['transactionId'] as int,
          amount: (payload['amount'] as num).toDouble(),
          type: (payload['type'] ?? '').toString(),
          note: payload['note']?.toString(),
          createdAt: payload['createdAt']?.toString(),
          attachmentPath: payload['attachmentPath']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'transaction.delete':
        await Api.deleteTransaction(
          payload['transactionId'] as int,
          queueOnFailure: false,
        );
        return;
      case 'supplier_transaction.create':
        await Api.createSupplierTransaction(
          businessId: payload['businessId'] as int,
          supplierId: payload['supplierId'] as int,
          amount: (payload['amount'] as num).toDouble(),
          type: (payload['type'] ?? '').toString(),
          note: payload['note']?.toString(),
          createdAt: payload['createdAt']?.toString(),
          attachmentPath: payload['attachmentPath']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'supplier_transaction.update':
        await Api.updateSupplierTransaction(
          transactionId: payload['transactionId'] as int,
          amount: (payload['amount'] as num).toDouble(),
          type: (payload['type'] ?? '').toString(),
          note: payload['note']?.toString(),
          createdAt: payload['createdAt']?.toString(),
          attachmentPath: payload['attachmentPath']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'supplier_transaction.delete':
        await Api.deleteSupplierTransaction(
          payload['transactionId'] as int,
          queueOnFailure: false,
        );
        return;
      case 'item.create':
        await Api.createItem(
          businessId: payload['businessId'] as int,
          type: (payload['type'] ?? '').toString(),
          name: (payload['name'] ?? '').toString(),
          unit: (payload['unit'] ?? '').toString(),
          salePrice: (payload['salePrice'] as num).toDouble(),
          purchasePrice: (payload['purchasePrice'] as num).toDouble(),
          taxIncluded: payload['taxIncluded'] == true,
          openingStock: payload['openingStock'] as int,
          lowStockAlert: payload['lowStockAlert'] as int,
          photoPath: payload['photoPath']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'item.update':
        await Api.updateItem(
          itemId: payload['itemId'] as int,
          name: payload['name']?.toString(),
          unit: payload['unit']?.toString(),
          taxIncluded: payload['taxIncluded'] as bool?,
          currentStock: payload['currentStock'] as int?,
          salePrice: (payload['salePrice'] as num?)?.toDouble(),
          purchasePrice: (payload['purchasePrice'] as num?)?.toDouble(),
          lowStockAlert: payload['lowStockAlert'] as int?,
          photoPath: payload['photoPath']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'item.stock':
        await Api.addItemStock(
          itemId: payload['itemId'] as int,
          type: (payload['type'] ?? '').toString(),
          quantity: payload['quantity'] as int,
          price: (payload['price'] as num).toDouble(),
          date: payload['date']?.toString(),
          note: payload['note']?.toString(),
          saleId: payload['saleId'] as int?,
          saleBillNumber: payload['saleBillNumber'] as int?,
          queueOnFailure: false,
        );
        return;
      case 'sale.create':
        await Api.createSale(
          businessId: payload['businessId'] as int,
          billNumber: payload['billNumber'] as int,
          date: (payload['date'] ?? '').toString(),
          partyName: payload['partyName']?.toString(),
          partyPhone: payload['partyPhone']?.toString(),
          customerId: payload['customerId'] as int?,
          paymentMode: (payload['paymentMode'] ?? '').toString(),
          dueDate: payload['dueDate']?.toString(),
          receivedAmount: (payload['receivedAmount'] as num?)?.toDouble(),
          paymentReference: payload['paymentReference']?.toString(),
          privateNotes: payload['privateNotes']?.toString(),
          photoPaths: (payload['photoPaths'] as List?)?.cast<String>(),
          manualAmount: (payload['manualAmount'] as num).toDouble(),
          lineItems:
              (payload['lineItems'] as List).cast<Map<String, dynamic>>(),
          additionalCharges: (payload['additionalCharges'] as List)
              .cast<Map<String, dynamic>>(),
          discountValue: (payload['discountValue'] as num).toDouble(),
          discountType: (payload['discountType'] ?? '').toString(),
          discountLabel: payload['discountLabel']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'sale.delete':
        await Api.deleteSale(
          payload['saleId'] as int,
          queueOnFailure: false,
        );
        return;
      case 'purchase.create':
        await Api.createPurchase(
          businessId: payload['businessId'] as int,
          purchaseNumber: payload['purchaseNumber'] as int,
          date: (payload['date'] ?? '').toString(),
          partyName: payload['partyName']?.toString(),
          partyPhone: payload['partyPhone']?.toString(),
          supplierId: payload['supplierId'] as int?,
          paymentMode: (payload['paymentMode'] ?? '').toString(),
          dueDate: payload['dueDate']?.toString(),
          paidAmount: (payload['paidAmount'] as num?)?.toDouble(),
          paymentReference: payload['paymentReference']?.toString(),
          privateNotes: payload['privateNotes']?.toString(),
          photoPaths: (payload['photoPaths'] as List?)?.cast<String>(),
          manualAmount: (payload['manualAmount'] as num).toDouble(),
          lineItems:
              (payload['lineItems'] as List).cast<Map<String, dynamic>>(),
          additionalCharges: (payload['additionalCharges'] as List)
              .cast<Map<String, dynamic>>(),
          discountValue: (payload['discountValue'] as num).toDouble(),
          discountType: (payload['discountType'] ?? '').toString(),
          discountLabel: payload['discountLabel']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'purchase.delete':
        await Api.deletePurchase(
          payload['purchaseId'] as int,
          queueOnFailure: false,
        );
        return;
      case 'expense.create':
        await Api.createExpense(
          businessId: payload['businessId'] as int,
          expenseNumber: payload['expenseNumber'] as int,
          date: (payload['date'] ?? '').toString(),
          categoryId: payload['categoryId'] as int?,
          categoryName: payload['categoryName']?.toString(),
          manualAmount: (payload['manualAmount'] as num).toDouble(),
          applyTax: payload['applyTax'] == true,
          items: (payload['items'] as List).cast<Map<String, dynamic>>(),
          queueOnFailure: false,
        );
        return;
      case 'cashbook.create':
        await Api.createCashbookEntry(
          businessId: payload['businessId'] as int,
          direction: (payload['direction'] ?? 'out').toString(),
          amount: (payload['amount'] as num).toDouble(),
          paymentMode: (payload['paymentMode'] ?? 'cash').toString(),
          date: (payload['date'] ?? '').toString(),
          note: payload['note']?.toString(),
          photoPath: payload['photoPath']?.toString(),
          queueOnFailure: false,
        );
        return;
      case 'sale_return.create':
        await Api.createSaleReturn(
          businessId: payload['business_id'] as int,
          returnNumber: payload['return_number'] as int,
          date: (payload['date'] ?? '').toString(),
          saleId: payload['sale_id'] as int?,
          customerId: payload['customer_id'] as int?,
          settlementMode: (payload['settlement_mode'] ?? '').toString(),
          manualAmount: (payload['manual_amount'] as num?)?.toDouble(),
          items: (payload['items'] as List?)?.cast<Map<String, dynamic>>(),
          queueOnFailure: false,
        );
        return;
      case 'sale_return.delete':
        await Api.deleteSaleReturn(
          payload['saleReturnId'] as int,
          queueOnFailure: false,
        );
        return;
      case 'sale_payment.create':
        await Api.createSalePayment(
          businessId: payload['business_id'] as int,
          paymentNumber: payload['payment_number'] as int,
          date: (payload['date'] ?? '').toString(),
          customerId: payload['customer_id'] as int,
          amount: (payload['amount'] as num).toDouble(),
          paymentMode: (payload['payment_mode'] ?? 'cash').toString(),
          note: payload['note']?.toString(),
          saleIds: (payload['sale_ids'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList(),
          queueOnFailure: false,
        );
        return;
      case 'purchase_return.create':
        await Api.createPurchaseReturn(
          businessId: payload['business_id'] as int,
          returnNumber: payload['return_number'] as int,
          date: (payload['date'] ?? '').toString(),
          purchaseId: payload['purchase_id'] as int?,
          supplierId: payload['supplier_id'] as int?,
          settlementMode: (payload['settlement_mode'] ?? '').toString(),
          manualAmount: (payload['manual_amount'] as num?)?.toDouble(),
          items: (payload['items'] as List?)?.cast<Map<String, dynamic>>(),
          queueOnFailure: false,
        );
        return;
      case 'purchase_return.delete':
        await Api.deletePurchaseReturn(
          payload['purchaseReturnId'] as int,
          queueOnFailure: false,
        );
        return;
      case 'purchase_payment.create':
        await Api.createPurchasePayment(
          businessId: payload['business_id'] as int,
          paymentNumber: payload['payment_number'] as int,
          date: (payload['date'] ?? '').toString(),
          supplierId: payload['supplier_id'] as int,
          amount: (payload['amount'] as num).toDouble(),
          paymentMode: (payload['payment_mode'] ?? 'cash').toString(),
          note: payload['note']?.toString(),
          purchaseIds: (payload['purchase_ids'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList(),
          queueOnFailure: false,
        );
        return;
      default:
        return;
    }
  }

  Future<bool> _repairCustomerReference({
    required int opId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    if (action != 'transaction.create' &&
        action != 'sale.create' &&
        action != 'sale_payment.create') {
      return false;
    }
    final businessId = _readInt(payload, ['businessId', 'business_id']);
    final oldCustomerId = _readInt(payload, ['customerId', 'customer_id']);
    if (businessId == null || oldCustomerId == null) return false;

    String name = (payload['customerName'] ?? payload['partyName'] ?? '')
        .toString()
        .trim();
    String? phone =
        (payload['customerPhone'] ?? payload['partyPhone'])?.toString().trim();
    final photoPath = payload['customerPhotoPath']?.toString();

    if (name.isEmpty) {
      final cached = await Api.findCachedCustomerByAnyId(
        businessId: businessId,
        anyId: oldCustomerId,
      );
      if (cached != null) {
        name = (cached['name'] ?? '').toString().trim();
        phone = (cached['phone'] ?? '').toString().trim();
      }
    }
    if (name.isEmpty) return false;

    final existingId = await _findMatchingServerCustomerId(
      businessId: businessId,
      name: name,
      phone: phone,
    );
    int? newCustomerId = existingId;
    if (newCustomerId == null) {
      final created = await Api.createCustomer(
        businessId: businessId,
        name: name,
        phone: phone?.isEmpty == true ? null : phone,
        photoPath: photoPath?.isEmpty == true ? null : photoPath,
        queueOnFailure: false,
      );
      final newCustomerIdRaw = created['id'];
      newCustomerId = newCustomerIdRaw is num
          ? newCustomerIdRaw.toInt()
          : int.tryParse(newCustomerIdRaw?.toString() ?? '');
    }
    if (newCustomerId == null) return false;

    if (payload.containsKey('customerId')) {
      payload['customerId'] = newCustomerId;
    }
    if (payload.containsKey('customer_id')) {
      payload['customer_id'] = newCustomerId;
    }
    if (payload.containsKey('partyName') &&
        (payload['partyName']?.toString().trim().isEmpty ?? true)) {
      payload['partyName'] = name;
    }
    if (payload.containsKey('partyPhone') &&
        (payload['partyPhone'] == null ||
            payload['partyPhone'].toString().trim().isEmpty)) {
      payload['partyPhone'] = phone;
    }

    await Db.instance.updatePendingOpPayload(opId, payload);
    await Db.instance.remapPendingCustomerId(
      fromId: oldCustomerId,
      toId: newCustomerId,
    );
    return true;
  }

  int? _readInt(Map<String, dynamic> payload, List<String> keys) {
    for (final k in keys) {
      final raw = payload[k];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      final v = int.tryParse(raw?.toString() ?? '');
      if (v != null) return v;
    }
    return null;
  }

  String _normPhone(String? s) => (s ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  String _normName(String? s) => (s ?? '').trim().toLowerCase();

  Future<int?> _findMatchingServerCustomerId({
    required int businessId,
    required String name,
    String? phone,
  }) async {
    final rows = await Api.getCustomers(businessId: businessId);
    final targetPhone = _normPhone(phone);
    final targetName = _normName(name);
    for (final r in rows) {
      if (r is! Map) continue;
      final m = Map<String, dynamic>.from(r);
      final idRaw = m['id'];
      final id =
          idRaw is num ? idRaw.toInt() : int.tryParse(idRaw?.toString() ?? '');
      if (id == null) continue;
      final rowPhone = _normPhone(m['phone']?.toString());
      final rowName = _normName(m['name']?.toString());
      if (targetPhone.isNotEmpty &&
          rowPhone.isNotEmpty &&
          targetPhone == rowPhone) {
        return id;
      }
      if (targetPhone.isEmpty &&
          targetName.isNotEmpty &&
          targetName == rowName) {
        return id;
      }
    }
    return null;
  }

  Future<bool> _isOnline() async {
    try {
      final uri = Uri.parse(Api.publicBaseUrl);
      final res = await http.get(uri, headers: const {
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 5));
      return res.statusCode >= 100;
    } catch (_) {
      try {
        final result = await InternetAddress.lookup('eliteposs.com');
        return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  bool _isNetworkError(Object e) {
    return e is SocketException ||
        e is HandshakeException ||
        e is http.ClientException;
  }

  bool _isInvalidCustomerError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('selected customer id is invalid') ||
        s.contains('customer_id');
  }
}
