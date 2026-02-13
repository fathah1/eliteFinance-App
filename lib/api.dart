import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Api {
  static const String baseUrl =
      'https://eliteposs.com/financeserver/public/api';

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
      await saveUser(data['user'] as Map<String, dynamic>);
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
      await saveUser(data['user'] as Map<String, dynamic>);
    }
    return data;
  }

  static Future<List<dynamic>> getBusinesses() async {
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

    return jsonDecode(res.body) as List<dynamic>;
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

  static Future<List<dynamic>> getCustomers({
    required int businessId,
  }) async {
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

    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createCustomer({
    required int businessId,
    required String name,
    String? phone,
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/customers'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'business_id': businessId,
        'name': name,
        'phone': phone,
      }),
    );

    if (res.statusCode != 201) {
      throw Exception('Create customer failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createTransaction({
    required int businessId,
    required int customerId,
    required double amount,
    required String type,
    String? note,
    String? createdAt,
    String? attachmentPath,
  }) async {
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
    return jsonDecode(body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateTransaction({
    required int transactionId,
    required double amount,
    required String type,
    String? note,
    String? createdAt,
    String? attachmentPath,
  }) async {
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
  }

  static Future<void> deleteTransaction(int transactionId) async {
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
  }

  static Future<List<dynamic>> getAllTransactions({
    required int businessId,
  }) async {
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

    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<List<dynamic>> getSuppliers({
    required int businessId,
  }) async {
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

    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createSupplier({
    required int businessId,
    required String name,
    String? phone,
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/suppliers'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'business_id': businessId,
        'name': name,
        'phone': phone,
      }),
    );

    if (res.statusCode != 201) {
      throw Exception('Create supplier failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getAllSupplierTransactions({
    required int businessId,
  }) async {
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

    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<List<dynamic>> getSupplierTransactions({
    required int supplierId,
  }) async {
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

    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createSupplierTransaction({
    required int businessId,
    required int supplierId,
    required double amount,
    required String type,
    String? note,
    String? createdAt,
    String? attachmentPath,
  }) async {
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
    return jsonDecode(body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateSupplierTransaction({
    required int transactionId,
    required double amount,
    required String type,
    String? note,
    String? createdAt,
    String? attachmentPath,
  }) async {
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
  }

  static Future<void> deleteSupplierTransaction(int transactionId) async {
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
  }

  static Future<List<dynamic>> getCustomerTransactions({
    required int customerId,
  }) async {
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

    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<List<dynamic>> getItems({
    required int businessId,
    required String type,
  }) async {
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

    return jsonDecode(res.body) as List<dynamic>;
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
  }) async {
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
    return jsonDecode(body) as Map<String, dynamic>;
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
  }) async {
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
  }) async {
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

    return jsonDecode(res.body) as List<dynamic>;
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
  }) async {
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
        req.files.add(await http.MultipartFile.fromPath('note_photos[]', path));
      }
    }
    final res = await req.send();
    final body = await res.stream.bytesToString();
    if (res.statusCode != 201) {
      throw Exception('Create sale failed: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }
}
