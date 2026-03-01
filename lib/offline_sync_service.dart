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

      final token = await Api.getToken();
      if (token == null || token.isEmpty) {
        await refreshStatus();
        return;
      }
      final online = await _isOnline();
      if (!online) {
        _setStatus(status.value.copyWith(isOnline: false, isSyncing: false));
        return;
      }
      _setStatus(status.value.copyWith(isOnline: true));

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
        await Api.createCustomer(
          businessId: payload['businessId'] as int,
          name: (payload['name'] ?? '').toString(),
          phone: payload['phone']?.toString(),
          photoPath: payload['photoPath']?.toString(),
          queueOnFailure: false,
        );
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
      default:
        return;
    }
  }

  Future<bool> _isOnline() async {
    try {
      final result = await InternetAddress.lookup('eliteposs.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _isNetworkError(Object e) {
    return e is SocketException ||
        e is HandshakeException ||
        e is http.ClientException;
  }
}
