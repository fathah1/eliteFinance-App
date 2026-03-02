import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_queue.dart';

class Api {
  static const String publicBaseUrl =
      'https://eliteposs.com/financeserver/public';
  static const String _publicOrigin = 'https://eliteposs.com';
  static const String _sharedHostMediaBase =
      'https://eliteposs.com/financeserver/storage/app/public';
  static const String baseUrl = '$publicBaseUrl/api';

  static String? resolveMediaUrl(dynamic rawValue) {
    if (rawValue == null) return null;
    var raw = rawValue.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final uri = Uri.tryParse(raw);
      if (uri == null) return raw;
      final host = uri.host.toLowerCase();
      final isLocalHost =
          host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
      if (!isLocalHost) {
        // Normalize accidental duplicated storage segments from legacy values.
        var fixedPath = uri.path
            .replaceAll('/public/storage/app/public/', '/storage/app/public/')
            .replaceAll('/public/storage/', '/storage/app/public/');
        if (fixedPath != uri.path) {
          return Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: fixedPath,
          ).toString();
        }
        // Shared-host compatibility:
        // convert /financeserver/public/storage/* to /financeserver/storage/app/public/*.
        if (uri.path.contains('/financeserver/public/storage/')) {
          final fixedPath = uri.path.replaceFirst(
              '/financeserver/public/storage/', '/financeserver/storage/app/public/');
          return Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: fixedPath,
          ).toString();
        }
        return raw;
      }

      final path = uri.path;
      const appPrefix = '/financeserver/public';
      final appIdx = path.indexOf(appPrefix);
      if (appIdx >= 0) {
        return '$_publicOrigin${path.substring(appIdx)}';
      }
      final storageIdx = path.indexOf('/storage/');
      if (storageIdx >= 0) {
        return '$_publicOrigin/financeserver${path.substring(storageIdx)}';
      }
      return raw;
    }

    raw = raw.replaceAll('\\', '/');
    while (raw.startsWith('/')) {
      raw = raw.substring(1);
    }
    if (raw.startsWith('public/')) {
      raw = raw.substring('public/'.length);
    }
    if (raw.startsWith('app/public/')) {
      raw = raw.substring('app/public/'.length);
    }
    if (raw.startsWith('storage/app/public/')) {
      raw = raw.substring('storage/app/public/'.length);
      return '$_sharedHostMediaBase/$raw';
    }
    if (raw.startsWith('storage/')) {
      raw = raw.substring('storage/'.length);
    }
    return '$_sharedHostMediaBase/$raw';
  }

  static List<dynamic> _onlyLive(List<dynamic> rows) {
    return rows.where((row) {
      if (row is Map) {
        final status = (row['del_status'] ?? 'live').toString().toLowerCase();
        return status == 'live';
      }
      return true;
    }).toList();
  }

  static List<dynamic> _extractLiveList(dynamic decoded) {
    if (decoded is List) return _onlyLive(decoded);
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is List) return _onlyLive(data);
    }
    return const [];
  }

  static bool _isNetworkError(Object e) {
    return e is SocketException ||
        e is HandshakeException ||
        e is http.ClientException;
  }

  static int _tempOfflineId() => -DateTime.now().millisecondsSinceEpoch;

  static Future<void> _cacheSet(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cache_$key', jsonEncode(data));
  }

  static Future<dynamic> _cacheGet(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cache_$key');
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<List<dynamic>> _getCachedLiveList(String key) async {
    final cached = await _cacheGet(key);
    return _extractLiveList(cached);
  }

  static Future<Map<String, dynamic>> _getCachedMap(String key) async {
    final cached = await _cacheGet(key);
    if (cached is Map<String, dynamic>) return cached;
    if (cached is Map) return Map<String, dynamic>.from(cached);
    return {};
  }

  static Future<void> _prependCachedList(
      String key, Map<String, dynamic> row) async {
    final current = await _getCachedLiveList(key);
    final next = <dynamic>[row, ...current];
    await _cacheSet(key, next);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_user', jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('current_user');
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user');
  }

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Login failed: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    await saveToken(data['token']);
    if (data['user'] is Map<String, dynamic>) {
      final user = Map<String, dynamic>.from(data['user'] as Map);
      if (data['permissions'] is Map<String, dynamic>) {
        user['permissions'] = data['permissions'];
      }
      if (data['business_ids'] is List) {
        user['business_ids'] = data['business_ids'];
      }
      await saveUser(user);
    }
    return data;
  }

  static Future<Map<String, dynamic>> register({
    required String username,
    required String name,
    required String password,
    required String businessName,
    String? phone,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'name': name,
        'phone': phone,
        'shop_name': businessName,
        'password': password,
      }),
    );

    if (res.statusCode != 201) {
      throw Exception('Register failed: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    await saveToken(data['token']);
    if (data['user'] is Map<String, dynamic>) {
      final user = Map<String, dynamic>.from(data['user'] as Map);
      if (data['permissions'] is Map<String, dynamic>) {
        user['permissions'] = data['permissions'];
      }
      if (data['business_ids'] is List) {
        user['business_ids'] = data['business_ids'];
      }
      await saveUser(user);
    }
    return data;
  }

  static Future<List<dynamic>> getStaffUsers() async {
    final token = await getToken();
    final res = await http.get(
      Uri.parse('$baseUrl/users/staff'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Fetch users failed: ${res.body}');
    }

    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createStaffUser({
    required String username,
    required String name,
    required String password,
    String? phone,
    required List<int> businessIds,
    required Map<String, dynamic> permissions,
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/users/staff'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'name': name,
        'password': password,
        'phone': phone,
        'business_ids': businessIds,
        'permissions': permissions,
      }),
    );

    if (res.statusCode != 201) {
      throw Exception('Create user failed: ${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getBusinesses() async {
    const cacheKey = 'businesses';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/businesses'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Fetch businesses failed: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<Map<String, dynamic>> createBusiness({
    required String name,
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/businesses'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'name': name,
      }),
    );

    if (res.statusCode != 201) {
      throw Exception('Create business failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> deleteBusiness(int businessId) async {
    final token = await getToken();
    final res = await http.delete(
      Uri.parse('$baseUrl/businesses/$businessId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Delete business failed: ${res.body}');
    }
  }

  static Future<List<dynamic>> getCustomers({
    required int businessId,
  }) async {
    final cacheKey = 'customers_b_$businessId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/customers?business_id=$businessId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Fetch customers failed: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<Map<String, dynamic>> createCustomer({
    required int businessId,
    required String name,
    String? phone,
    String? photoPath,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final req =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/customers'));
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['business_id'] = businessId.toString();
      req.fields['name'] = name;
      if (phone != null && phone.trim().isNotEmpty) {
        req.fields['phone'] = phone.trim();
      }
      if (photoPath != null && photoPath.trim().isNotEmpty) {
        req.files.add(await http.MultipartFile.fromPath('photo', photoPath));
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 201) {
        throw Exception('Create customer failed: $body');
      }
      final created = jsonDecode(body) as Map<String, dynamic>;
      await _prependCachedList('customers_b_$businessId', created);
      return created;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'customer.create',
        payload: {
          'businessId': businessId,
          'name': name,
          'phone': phone,
          'photoPath': photoPath,
        },
      );
      final local = {
        'id': _tempOfflineId(),
        'business_id': businessId,
        'name': name,
        'phone': phone,
        'offline_queued': true,
      };
      await _prependCachedList('customers_b_$businessId', local);
      return local;
    }
  }

  static Future<void> deleteCustomer(
    int customerId, {
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final res = await http.delete(
        Uri.parse('$baseUrl/customers/$customerId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Delete customer failed: ${res.body}');
      }
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'customer.delete',
        payload: {'customerId': customerId},
      );
    }
  }

  static Future<Map<String, dynamic>> updateCustomer({
    required int customerId,
    required String name,
    String? phone,
    String? photoPath,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/customers/$customerId'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['_method'] = 'PUT';
      req.fields['name'] = name;
      if (phone != null && phone.trim().isNotEmpty) {
        req.fields['phone'] = phone.trim();
      }
      if (photoPath != null && photoPath.trim().isNotEmpty) {
        req.files.add(await http.MultipartFile.fromPath('photo', photoPath));
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200) {
        throw Exception('Update customer failed: $body');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'customer.update',
        payload: {
          'customerId': customerId,
          'name': name,
          'phone': phone,
          'photoPath': photoPath,
        },
      );
      return {
        'id': customerId,
        'name': name,
        'phone': phone,
        'offline_queued': true,
      };
    }
  }

  static Future<Map<String, dynamic>> createTransaction({
    required int businessId,
    required int customerId,
    required double amount,
    required String type,
    String? note,
    String? createdAt,
    String? attachmentPath,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final uri = Uri.parse('$baseUrl/transactions');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['business_id'] = businessId.toString();
      req.fields['customer_id'] = customerId.toString();
      req.fields['amount'] = amount.toString();
      req.fields['type'] = type;
      if (note != null) req.fields['note'] = note;
      if (createdAt != null) req.fields['created_at'] = createdAt;
      if (attachmentPath != null) {
        req.files.add(await http.MultipartFile.fromPath(
          'attachment',
          attachmentPath,
        ));
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 201) {
        throw Exception('Create transaction failed: $body');
      }
      final created = jsonDecode(body) as Map<String, dynamic>;
      await _prependCachedList('customer_tx_c_$customerId', created);
      await _prependCachedList('transactions_b_$businessId', created);
      return created;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'transaction.create',
        payload: {
          'businessId': businessId,
          'customerId': customerId,
          'amount': amount,
          'type': type,
          'note': note,
          'createdAt': createdAt,
          'attachmentPath': attachmentPath,
        },
      );
      final local = {
        'id': _tempOfflineId(),
        'business_id': businessId,
        'customer_id': customerId,
        'amount': amount,
        'type': type,
        'note': note,
        'created_at': createdAt ?? DateTime.now().toIso8601String(),
        'offline_queued': true,
      };
      await _prependCachedList('customer_tx_c_$customerId', local);
      await _prependCachedList('transactions_b_$businessId', local);
      return local;
    }
  }

  static Future<Map<String, dynamic>> updateTransaction({
    required int transactionId,
    required double amount,
    required String type,
    String? note,
    String? createdAt,
    String? attachmentPath,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final uri = Uri.parse('$baseUrl/transactions/$transactionId');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['_method'] = 'PUT';
      req.fields['amount'] = amount.toString();
      req.fields['type'] = type;
      if (note != null) req.fields['note'] = note;
      if (createdAt != null) req.fields['created_at'] = createdAt;
      if (attachmentPath != null) {
        req.files.add(await http.MultipartFile.fromPath(
          'attachment',
          attachmentPath,
        ));
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200) {
        throw Exception('Update transaction failed: $body');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'transaction.update',
        payload: {
          'transactionId': transactionId,
          'amount': amount,
          'type': type,
          'note': note,
          'createdAt': createdAt,
          'attachmentPath': attachmentPath,
        },
      );
      return {
        'id': transactionId,
        'amount': amount,
        'type': type,
        'note': note,
        'created_at': createdAt ?? DateTime.now().toIso8601String(),
        'offline_queued': true,
      };
    }
  }

  static Future<void> deleteTransaction(
    int transactionId, {
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final res = await http.delete(
        Uri.parse('$baseUrl/transactions/$transactionId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Delete transaction failed: ${res.body}');
      }
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'transaction.delete',
        payload: {'transactionId': transactionId},
      );
    }
  }

  static Future<List<dynamic>> getAllTransactions({
    required int businessId,
  }) async {
    final cacheKey = 'transactions_b_$businessId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/transactions?business_id=$businessId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Fetch transactions failed: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<List<dynamic>> getSuppliers({
    required int businessId,
  }) async {
    final cacheKey = 'suppliers_b_$businessId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/suppliers?business_id=$businessId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Fetch suppliers failed: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<Map<String, dynamic>> createSupplier({
    required int businessId,
    required String name,
    String? phone,
    String? photoPath,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final req =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/suppliers'));
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['business_id'] = businessId.toString();
      req.fields['name'] = name;
      if (phone != null && phone.trim().isNotEmpty) {
        req.fields['phone'] = phone.trim();
      }
      if (photoPath != null && photoPath.trim().isNotEmpty) {
        req.files.add(await http.MultipartFile.fromPath('photo', photoPath));
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 201) {
        throw Exception('Create supplier failed: $body');
      }
      final created = jsonDecode(body) as Map<String, dynamic>;
      await _prependCachedList('suppliers_b_$businessId', created);
      return created;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'supplier.create',
        payload: {
          'businessId': businessId,
          'name': name,
          'phone': phone,
          'photoPath': photoPath,
        },
      );
      final local = {
        'id': _tempOfflineId(),
        'business_id': businessId,
        'name': name,
        'phone': phone,
        'offline_queued': true,
      };
      await _prependCachedList('suppliers_b_$businessId', local);
      return local;
    }
  }

  static Future<void> deleteSupplier(
    int supplierId, {
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final res = await http.delete(
        Uri.parse('$baseUrl/suppliers/$supplierId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Delete supplier failed: ${res.body}');
      }
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'supplier.delete',
        payload: {'supplierId': supplierId},
      );
    }
  }

  static Future<Map<String, dynamic>> updateSupplier({
    required int supplierId,
    required String name,
    String? phone,
    String? photoPath,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/suppliers/$supplierId'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['_method'] = 'PUT';
      req.fields['name'] = name;
      if (phone != null && phone.trim().isNotEmpty) {
        req.fields['phone'] = phone.trim();
      }
      if (photoPath != null && photoPath.trim().isNotEmpty) {
        req.files.add(await http.MultipartFile.fromPath('photo', photoPath));
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200) {
        throw Exception('Update supplier failed: $body');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'supplier.update',
        payload: {
          'supplierId': supplierId,
          'name': name,
          'phone': phone,
          'photoPath': photoPath,
        },
      );
      return {
        'id': supplierId,
        'name': name,
        'phone': phone,
        'offline_queued': true,
      };
    }
  }

  static Future<List<dynamic>> getAllSupplierTransactions({
    required int businessId,
  }) async {
    final cacheKey = 'supplier_transactions_b_$businessId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/supplier-transactions?business_id=$businessId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Fetch supplier transactions failed: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<List<dynamic>> getSupplierTransactions({
    required int supplierId,
  }) async {
    final cacheKey = 'supplier_tx_s_$supplierId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/suppliers/$supplierId/transactions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Fetch supplier transactions failed: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<Map<String, dynamic>> createSupplierTransaction({
    required int businessId,
    required int supplierId,
    required double amount,
    required String type,
    String? note,
    String? createdAt,
    String? attachmentPath,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final uri = Uri.parse('$baseUrl/supplier-transactions');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['business_id'] = businessId.toString();
      req.fields['supplier_id'] = supplierId.toString();
      req.fields['amount'] = amount.toString();
      req.fields['type'] = type;
      if (note != null) req.fields['note'] = note;
      if (createdAt != null) req.fields['created_at'] = createdAt;
      if (attachmentPath != null) {
        req.files.add(await http.MultipartFile.fromPath(
          'attachment',
          attachmentPath,
        ));
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 201) {
        throw Exception('Create supplier transaction failed: $body');
      }
      final created = jsonDecode(body) as Map<String, dynamic>;
      await _prependCachedList('supplier_tx_s_$supplierId', created);
      await _prependCachedList('supplier_transactions_b_$businessId', created);
      return created;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'supplier_transaction.create',
        payload: {
          'businessId': businessId,
          'supplierId': supplierId,
          'amount': amount,
          'type': type,
          'note': note,
          'createdAt': createdAt,
          'attachmentPath': attachmentPath,
        },
      );
      final local = {
        'id': _tempOfflineId(),
        'business_id': businessId,
        'supplier_id': supplierId,
        'amount': amount,
        'type': type,
        'note': note,
        'created_at': createdAt ?? DateTime.now().toIso8601String(),
        'offline_queued': true,
      };
      await _prependCachedList('supplier_tx_s_$supplierId', local);
      await _prependCachedList('supplier_transactions_b_$businessId', local);
      return local;
    }
  }

  static Future<Map<String, dynamic>> updateSupplierTransaction({
    required int transactionId,
    required double amount,
    required String type,
    String? note,
    String? createdAt,
    String? attachmentPath,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final uri = Uri.parse('$baseUrl/supplier-transactions/$transactionId');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['_method'] = 'PUT';
      req.fields['amount'] = amount.toString();
      req.fields['type'] = type;
      if (note != null) req.fields['note'] = note;
      if (createdAt != null) req.fields['created_at'] = createdAt;
      if (attachmentPath != null) {
        req.files.add(await http.MultipartFile.fromPath(
          'attachment',
          attachmentPath,
        ));
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200) {
        throw Exception('Update supplier transaction failed: $body');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'supplier_transaction.update',
        payload: {
          'transactionId': transactionId,
          'amount': amount,
          'type': type,
          'note': note,
          'createdAt': createdAt,
          'attachmentPath': attachmentPath,
        },
      );
      return {
        'id': transactionId,
        'amount': amount,
        'type': type,
        'note': note,
        'created_at': createdAt ?? DateTime.now().toIso8601String(),
        'offline_queued': true,
      };
    }
  }

  static Future<void> deleteSupplierTransaction(
    int transactionId, {
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final res = await http.delete(
        Uri.parse('$baseUrl/supplier-transactions/$transactionId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Delete supplier transaction failed: ${res.body}');
      }
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'supplier_transaction.delete',
        payload: {'transactionId': transactionId},
      );
    }
  }

  static Future<List<dynamic>> getCustomerTransactions({
    required int customerId,
  }) async {
    final cacheKey = 'customer_tx_c_$customerId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/customers/$customerId/transactions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Fetch customer transactions failed: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<List<dynamic>> getItems({
    required int businessId,
    required String type,
  }) async {
    final cacheKey = 'items_b_${businessId}_t_$type';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/items?business_id=$businessId&type=$type'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Fetch items failed: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<Map<String, dynamic>> createItem({
    required int businessId,
    required String type,
    required String name,
    required String unit,
    required double salePrice,
    required double purchasePrice,
    required bool taxIncluded,
    required int openingStock,
    required int lowStockAlert,
    String? photoPath,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final uri = Uri.parse('$baseUrl/items');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['business_id'] = businessId.toString();
      req.fields['type'] = type;
      req.fields['name'] = name;
      req.fields['unit'] = unit;
      req.fields['sale_price'] = salePrice.toString();
      req.fields['purchase_price'] = purchasePrice.toString();
      req.fields['tax_included'] = taxIncluded ? '1' : '0';
      req.fields['opening_stock'] = openingStock.toString();
      req.fields['low_stock_alert'] = lowStockAlert.toString();
      if (photoPath != null) {
        req.files.add(await http.MultipartFile.fromPath('photo', photoPath));
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 201) {
        throw Exception('Create item failed: $body');
      }
      final created = jsonDecode(body) as Map<String, dynamic>;
      await _prependCachedList('items_b_${businessId}_t_$type', created);
      return created;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'item.create',
        payload: {
          'businessId': businessId,
          'type': type,
          'name': name,
          'unit': unit,
          'salePrice': salePrice,
          'purchasePrice': purchasePrice,
          'taxIncluded': taxIncluded,
          'openingStock': openingStock,
          'lowStockAlert': lowStockAlert,
          'photoPath': photoPath,
        },
      );
      final local = {
        'id': _tempOfflineId(),
        'business_id': businessId,
        'type': type,
        'name': name,
        'unit': unit,
        'sale_price': salePrice,
        'purchase_price': purchasePrice,
        'current_stock': openingStock,
        'low_stock_alert': lowStockAlert,
        'offline_queued': true,
      };
      await _prependCachedList('items_b_${businessId}_t_$type', local);
      return local;
    }
  }

  static Future<Map<String, dynamic>> updateItem({
    required int itemId,
    String? name,
    String? unit,
    bool? taxIncluded,
    int? currentStock,
    double? salePrice,
    double? purchasePrice,
    int? lowStockAlert,
    String? photoPath,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      debugPrint(
          'PUT /items/$itemId name=$name unit=$unit sale=$salePrice purchase=$purchasePrice low=$lowStockAlert');
      final uri = Uri.parse('$baseUrl/items/$itemId');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['_method'] = 'PUT';
      if (name != null) {
        req.fields['name'] = name;
      }
      if (unit != null) {
        req.fields['unit'] = unit;
      }
      if (taxIncluded != null) {
        req.fields['tax_included'] = taxIncluded ? '1' : '0';
      }
      if (currentStock != null) {
        req.fields['current_stock'] = currentStock.toString();
      }
      if (salePrice != null) {
        req.fields['sale_price'] = salePrice.toString();
      }
      if (purchasePrice != null) {
        req.fields['purchase_price'] = purchasePrice.toString();
      }
      if (lowStockAlert != null) {
        req.fields['low_stock_alert'] = lowStockAlert.toString();
      }
      if (photoPath != null && !photoPath.startsWith('http')) {
        req.files.add(await http.MultipartFile.fromPath('photo', photoPath));
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200) {
        debugPrint('Update item response: ${res.statusCode} $body');
        throw Exception('Update item failed: $body');
      }
      debugPrint('Update item response: ${res.statusCode} $body');
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'item.update',
        payload: {
          'itemId': itemId,
          'name': name,
          'unit': unit,
          'taxIncluded': taxIncluded,
          'currentStock': currentStock,
          'salePrice': salePrice,
          'purchasePrice': purchasePrice,
          'lowStockAlert': lowStockAlert,
          'photoPath': photoPath,
        },
      );
      return {
        'id': itemId,
        'name': name,
        'unit': unit,
        'sale_price': salePrice,
        'purchase_price': purchasePrice,
        'low_stock_alert': lowStockAlert,
        'offline_queued': true,
      };
    }
  }

  static Future<Map<String, dynamic>> addItemStock({
    required int itemId,
    required String type, // in | out
    required int quantity,
    required double price,
    String? date,
    String? note,
    int? saleId,
    int? saleBillNumber,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      debugPrint(
          'POST /items/$itemId/stock type=$type qty=$quantity price=$price date=$date');
      final res = await http.post(
        Uri.parse('$baseUrl/items/$itemId/stock'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'type': type,
          'quantity': quantity,
          'price': price,
          'date': date,
          'note': note,
          'sale_id': saleId,
          'sale_bill_number': saleBillNumber,
        }),
      );

      if (res.statusCode != 200) {
        debugPrint('Stock response: ${res.statusCode} ${res.body}');
        throw Exception('Add stock failed: ${res.body}');
      }

      debugPrint('Stock response: ${res.statusCode} ${res.body}');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'item.stock',
        payload: {
          'itemId': itemId,
          'type': type,
          'quantity': quantity,
          'price': price,
          'date': date,
          'note': note,
          'saleId': saleId,
          'saleBillNumber': saleBillNumber,
        },
      );
      return {
        'item_id': itemId,
        'type': type,
        'quantity': quantity,
        'price': price,
        'offline_queued': true,
      };
    }
  }

  static Future<List<dynamic>> getItemMovements({
    required int itemId,
  }) async {
    final token = await getToken();
    debugPrint('GET /items/$itemId/movements');
    final res = await http.get(
      Uri.parse('$baseUrl/items/$itemId/movements'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode != 200) {
      debugPrint('Movements response: ${res.statusCode} ${res.body}');
      throw Exception('Fetch item movements failed: ${res.body}');
    }

    debugPrint('Movements response: ${res.statusCode} ${res.body}');
    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<List<dynamic>> getSales({
    required int businessId,
  }) async {
    final cacheKey = 'sales_b_$businessId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/sales?business_id=$businessId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Fetch sales failed: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<Map<String, dynamic>> createSale({
    required int businessId,
    required int billNumber,
    required String date,
    String? partyName,
    String? partyPhone,
    int? customerId,
    required String paymentMode, // unpaid|cash|card
    String? dueDate,
    double? receivedAmount,
    String? paymentReference,
    String? privateNotes,
    List<String>? photoPaths,
    required double manualAmount,
    required List<Map<String, dynamic>> lineItems,
    required List<Map<String, dynamic>> additionalCharges,
    required double discountValue,
    required String discountType,
    String? discountLabel,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/sales'));
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['business_id'] = businessId.toString();
      req.fields['bill_number'] = billNumber.toString();
      req.fields['date'] = date;
      req.fields['payment_mode'] = paymentMode;
      req.fields['manual_amount'] = manualAmount.toString();
      req.fields['line_items'] = jsonEncode(lineItems);
      req.fields['additional_charges'] = jsonEncode(additionalCharges);
      req.fields['discount_value'] = discountValue.toString();
      req.fields['discount_type'] = discountType;
      if (partyName != null && partyName.trim().isNotEmpty) {
        req.fields['party_name'] = partyName.trim();
      }
      if (partyPhone != null && partyPhone.trim().isNotEmpty) {
        req.fields['party_phone'] = partyPhone.trim();
      }
      if (customerId != null) {
        req.fields['customer_id'] = customerId.toString();
      }
      if (dueDate != null && dueDate.isNotEmpty) {
        req.fields['due_date'] = dueDate;
      }
      if (receivedAmount != null) {
        req.fields['received_amount'] = receivedAmount.toString();
      }
      if (paymentReference != null && paymentReference.trim().isNotEmpty) {
        req.fields['payment_reference'] = paymentReference.trim();
      }
      if (privateNotes != null && privateNotes.trim().isNotEmpty) {
        req.fields['private_notes'] = privateNotes.trim();
      }
      if (discountLabel != null && discountLabel.trim().isNotEmpty) {
        req.fields['discount_label'] = discountLabel.trim();
      }
      if (photoPaths != null) {
        for (final path in photoPaths) {
          if (path.trim().isEmpty) continue;
          req.files
              .add(await http.MultipartFile.fromPath('note_photos[]', path));
        }
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 201) {
        throw Exception('Create sale failed: $body');
      }
      final created = jsonDecode(body) as Map<String, dynamic>;
      await _prependCachedList('sales_b_$businessId', created);
      return created;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'sale.create',
        payload: {
          'businessId': businessId,
          'billNumber': billNumber,
          'date': date,
          'partyName': partyName,
          'partyPhone': partyPhone,
          'customerId': customerId,
          'paymentMode': paymentMode,
          'dueDate': dueDate,
          'receivedAmount': receivedAmount,
          'paymentReference': paymentReference,
          'privateNotes': privateNotes,
          'photoPaths': photoPaths ?? const <String>[],
          'manualAmount': manualAmount,
          'lineItems': lineItems,
          'additionalCharges': additionalCharges,
          'discountValue': discountValue,
          'discountType': discountType,
          'discountLabel': discountLabel,
        },
      );
      final local = {
        'id': _tempOfflineId(),
        'business_id': businessId,
        'bill_number': billNumber,
        'date': date,
        'payment_mode': paymentMode,
        'amount': manualAmount,
        'offline_queued': true,
      };
      await _prependCachedList('sales_b_$businessId', local);
      return local;
    }
  }

  static Future<void> deleteSale(
    int saleId, {
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final res = await http.delete(
        Uri.parse('$baseUrl/sales/$saleId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Delete sale failed: ${res.body}');
      }
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'sale.delete',
        payload: {'saleId': saleId},
      );
    }
  }

  static Future<Map<String, dynamic>> createSaleReturn({
    required int businessId,
    required int returnNumber,
    required String date,
    int? saleId,
    int? customerId,
    required String settlementMode, // credit_party|cash|card
    double? manualAmount,
    List<Map<String, dynamic>>? items,
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/sales/returns'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'business_id': businessId,
        'return_number': returnNumber,
        'date': date,
        'sale_id': saleId,
        'customer_id': customerId,
        'settlement_mode': settlementMode,
        'manual_amount': manualAmount,
        'items': items ?? const [],
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('Create sale return failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createSalePayment({
    required int businessId,
    required int paymentNumber,
    required String date,
    required int customerId,
    required double amount,
    required String paymentMode, // cash|card
    String? note,
    List<int>? saleIds,
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/sales/payments'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'business_id': businessId,
        'payment_number': paymentNumber,
        'date': date,
        'customer_id': customerId,
        'amount': amount,
        'payment_mode': paymentMode,
        'note': note,
        'sale_ids': saleIds ?? const [],
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('Create sale payment failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getSaleReturns({
    required int businessId,
  }) async {
    final token = await getToken();
    final res = await http.get(
      Uri.parse('$baseUrl/sales/returns?business_id=$businessId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Fetch sale returns failed: ${res.body}');
    }
    return _extractLiveList(jsonDecode(res.body));
  }

  static Future<void> deleteSaleReturn(int saleReturnId) async {
    final token = await getToken();
    final res = await http.delete(
      Uri.parse('$baseUrl/sales/returns/$saleReturnId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Delete sale return failed: ${res.body}');
    }
  }

  static Future<List<dynamic>> getPurchases({
    required int businessId,
  }) async {
    final cacheKey = 'purchases_b_$businessId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/purchases?business_id=$businessId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('Fetch purchases failed: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<Map<String, dynamic>> createPurchase({
    required int businessId,
    required int purchaseNumber,
    required String date,
    String? partyName,
    String? partyPhone,
    int? supplierId,
    required String paymentMode, // unpaid|cash|card
    String? dueDate,
    double? paidAmount,
    String? paymentReference,
    String? privateNotes,
    List<String>? photoPaths,
    required double manualAmount,
    required List<Map<String, dynamic>> lineItems,
    required List<Map<String, dynamic>> additionalCharges,
    required double discountValue,
    required String discountType,
    String? discountLabel,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final req =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/purchases'));
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['Accept'] = 'application/json';
      req.fields['business_id'] = businessId.toString();
      req.fields['purchase_number'] = purchaseNumber.toString();
      req.fields['date'] = date;
      req.fields['payment_mode'] = paymentMode;
      req.fields['manual_amount'] = manualAmount.toString();
      req.fields['line_items'] = jsonEncode(lineItems);
      req.fields['additional_charges'] = jsonEncode(additionalCharges);
      req.fields['discount_value'] = discountValue.toString();
      req.fields['discount_type'] = discountType;
      if (partyName != null && partyName.trim().isNotEmpty) {
        req.fields['party_name'] = partyName.trim();
      }
      if (partyPhone != null && partyPhone.trim().isNotEmpty) {
        req.fields['party_phone'] = partyPhone.trim();
      }
      if (supplierId != null) {
        req.fields['supplier_id'] = supplierId.toString();
      }
      if (dueDate != null && dueDate.isNotEmpty) {
        req.fields['due_date'] = dueDate;
      }
      if (paidAmount != null) {
        req.fields['paid_amount'] = paidAmount.toString();
      }
      if (paymentReference != null && paymentReference.trim().isNotEmpty) {
        req.fields['payment_reference'] = paymentReference.trim();
      }
      if (privateNotes != null && privateNotes.trim().isNotEmpty) {
        req.fields['private_notes'] = privateNotes.trim();
      }
      if (discountLabel != null && discountLabel.trim().isNotEmpty) {
        req.fields['discount_label'] = discountLabel.trim();
      }
      if (photoPaths != null) {
        for (final path in photoPaths) {
          if (path.trim().isEmpty) continue;
          req.files
              .add(await http.MultipartFile.fromPath('note_photos[]', path));
        }
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode != 201) {
        throw Exception('Create purchase failed: $body');
      }
      final created = jsonDecode(body) as Map<String, dynamic>;
      await _prependCachedList('purchases_b_$businessId', created);
      return created;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'purchase.create',
        payload: {
          'businessId': businessId,
          'purchaseNumber': purchaseNumber,
          'date': date,
          'partyName': partyName,
          'partyPhone': partyPhone,
          'supplierId': supplierId,
          'paymentMode': paymentMode,
          'dueDate': dueDate,
          'paidAmount': paidAmount,
          'paymentReference': paymentReference,
          'privateNotes': privateNotes,
          'photoPaths': photoPaths ?? const <String>[],
          'manualAmount': manualAmount,
          'lineItems': lineItems,
          'additionalCharges': additionalCharges,
          'discountValue': discountValue,
          'discountType': discountType,
          'discountLabel': discountLabel,
        },
      );
      final local = {
        'id': _tempOfflineId(),
        'business_id': businessId,
        'purchase_number': purchaseNumber,
        'date': date,
        'payment_mode': paymentMode,
        'amount': manualAmount,
        'offline_queued': true,
      };
      await _prependCachedList('purchases_b_$businessId', local);
      return local;
    }
  }

  static Future<void> deletePurchase(
    int purchaseId, {
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final res = await http.delete(
        Uri.parse('$baseUrl/purchases/$purchaseId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Delete purchase failed: ${res.body}');
      }
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'purchase.delete',
        payload: {'purchaseId': purchaseId},
      );
    }
  }

  static Future<Map<String, dynamic>> createPurchaseReturn({
    required int businessId,
    required int returnNumber,
    required String date,
    int? purchaseId,
    int? supplierId,
    required String settlementMode, // credit_party|cash|card
    double? manualAmount,
    List<Map<String, dynamic>>? items,
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/purchases/returns'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'business_id': businessId,
        'return_number': returnNumber,
        'date': date,
        'purchase_id': purchaseId,
        'supplier_id': supplierId,
        'settlement_mode': settlementMode,
        'manual_amount': manualAmount,
        'items': items ?? const [],
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('Create purchase return failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createPurchasePayment({
    required int businessId,
    required int paymentNumber,
    required String date,
    required int supplierId,
    required double amount,
    required String paymentMode, // cash|card
    String? note,
    List<int>? purchaseIds,
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/purchases/payments'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'business_id': businessId,
        'payment_number': paymentNumber,
        'date': date,
        'supplier_id': supplierId,
        'amount': amount,
        'payment_mode': paymentMode,
        'note': note,
        'purchase_ids': purchaseIds ?? const [],
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('Create purchase payment failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getPurchaseReturns({
    required int businessId,
  }) async {
    final token = await getToken();
    final res = await http.get(
      Uri.parse('$baseUrl/purchases/returns?business_id=$businessId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Fetch purchase returns failed: ${res.body}');
    }
    return _extractLiveList(jsonDecode(res.body));
  }

  static Future<void> deletePurchaseReturn(int purchaseReturnId) async {
    final token = await getToken();
    final res = await http.delete(
      Uri.parse('$baseUrl/purchases/returns/$purchaseReturnId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Delete purchase return failed: ${res.body}');
    }
  }

  static Future<List<dynamic>> getExpenseCategories({
    required int businessId,
  }) async {
    final cacheKey = 'expense_categories_b_$businessId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/expense-categories?business_id=$businessId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Fetch expense categories failed: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<Map<String, dynamic>> createExpenseCategory({
    required int businessId,
    required String name,
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/expense-categories'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'business_id': businessId,
        'name': name,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('Create expense category failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getExpenses({
    required int businessId,
  }) async {
    final cacheKey = 'expenses_b_$businessId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/expenses?business_id=$businessId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Fetch expenses failed: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<Map<String, dynamic>> createExpense({
    required int businessId,
    required int expenseNumber,
    required String date,
    int? categoryId,
    String? categoryName,
    required double manualAmount,
    bool applyTax = false,
    required List<Map<String, dynamic>> items,
    bool queueOnFailure = true,
  }) async {
    try {
      final token = await getToken();
      final res = await http.post(
        Uri.parse('$baseUrl/expenses'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'business_id': businessId,
          'expense_number': expenseNumber,
          'date': date,
          'category_id': categoryId,
          'category_name': categoryName,
          'manual_amount': manualAmount,
          'apply_tax': applyTax,
          'items': items,
        }),
      );
      if (res.statusCode != 201) {
        throw Exception('Create expense failed: ${res.body}');
      }
      final created = jsonDecode(res.body) as Map<String, dynamic>;
      await _prependCachedList('expenses_b_$businessId', created);
      return created;
    } catch (e) {
      if (!queueOnFailure || !_isNetworkError(e)) rethrow;
      await OfflineQueue.push(
        action: 'expense.create',
        payload: {
          'businessId': businessId,
          'expenseNumber': expenseNumber,
          'date': date,
          'categoryId': categoryId,
          'categoryName': categoryName,
          'manualAmount': manualAmount,
          'applyTax': applyTax,
          'items': items,
        },
      );
      final local = {
        'id': _tempOfflineId(),
        'business_id': businessId,
        'expense_number': expenseNumber,
        'date': date,
        'amount': manualAmount,
        'offline_queued': true,
      };
      await _prependCachedList('expenses_b_$businessId', local);
      return local;
    }
  }

  static Future<List<dynamic>> getExpenseItems({
    required int businessId,
  }) async {
    final cacheKey = 'expense_items_b_$businessId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/expense-items?business_id=$businessId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Fetch expense items failed: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      await _cacheSet(cacheKey, decoded);
      return _extractLiveList(decoded);
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedLiveList(cacheKey);
    }
  }

  static Future<Map<String, dynamic>> createExpenseItem({
    required int businessId,
    required String name,
    required double rate,
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/expense-items'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'business_id': businessId,
        'name': name,
        'rate': rate,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('Create expense item failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateExpenseItem({
    required int id,
    required String name,
    required double rate,
  }) async {
    final token = await getToken();
    final res = await http.put(
      Uri.parse('$baseUrl/expense-items/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'rate': rate,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Update expense item failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> deleteExpenseItem(int id) async {
    final token = await getToken();
    final res = await http.delete(
      Uri.parse('$baseUrl/expense-items/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Delete expense item failed: ${res.body}');
    }
  }

  static Future<Map<String, dynamic>> getExpense({
    required int id,
  }) async {
    final token = await getToken();
    final res = await http.get(
      Uri.parse('$baseUrl/expenses/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Fetch expense failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateExpense({
    required int id,
    required int expenseNumber,
    required String date,
    int? categoryId,
    String? categoryName,
    required double manualAmount,
    bool applyTax = false,
    required List<Map<String, dynamic>> items,
  }) async {
    final token = await getToken();
    final res = await http.put(
      Uri.parse('$baseUrl/expenses/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'expense_number': expenseNumber,
        'date': date,
        'category_id': categoryId,
        'category_name': categoryName,
        'manual_amount': manualAmount,
        'apply_tax': applyTax,
        'items': items,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Update expense failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> deleteExpense({
    required int id,
  }) async {
    final token = await getToken();
    final res = await http.delete(
      Uri.parse('$baseUrl/expenses/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Delete expense failed: ${res.body}');
    }
  }

  static Future<Map<String, dynamic>> getCashbook({
    required int businessId,
  }) async {
    final cacheKey = 'cashbook_b_$businessId';
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/cashbook?business_id=$businessId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Fetch cashbook failed: ${res.body}');
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      await _cacheSet(cacheKey, decoded);
      return decoded;
    } catch (e) {
      if (!_isNetworkError(e)) rethrow;
      return _getCachedMap(cacheKey);
    }
  }
}
