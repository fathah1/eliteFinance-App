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

    debugPrint('GET /customers?business_id=$businessId');
    debugPrint('Response: ${res.body}');

    if (res.statusCode != 200) {
      throw Exception('Fetch customers failed: ${res.body}');
    }




    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createCustomer({
    required int businessId,
    required String name,
    String? phone,
    double openingBalance = 0,
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
        'opening_balance': openingBalance,
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
  }) async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/transactions'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'business_id': businessId,
        'customer_id': customerId,
        'amount': amount,
        'type': type,
        'note': note,
        'created_at': createdAt,
      }),
    );

    if (res.statusCode != 201) {
      throw Exception('Create transaction failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateTransaction({
    required int transactionId,
    required double amount,
    required String type,
    String? note,
    String? createdAt,
  }) async {
    final token = await getToken();
    final res = await http.put(
      Uri.parse('$baseUrl/transactions/$transactionId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'amount': amount,
        'type': type,
        'note': note,
        'created_at': createdAt,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Update transaction failed: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
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
}
