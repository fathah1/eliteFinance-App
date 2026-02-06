import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class Db {
  Db._();
  static final Db instance = Db._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'khata.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            phone TEXT,
            shop_name TEXT,
            settings TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER,
            name TEXT NOT NULL,
            phone TEXT,
            opening_balance REAL NOT NULL DEFAULT 0,
            is_archived INTEGER NOT NULL DEFAULT 0,
            synced INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER,
            customer_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE customers ADD COLUMN server_id INTEGER');
          await db.execute(
              'ALTER TABLE customers ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE transactions ADD COLUMN server_id INTEGER');
        }
      },
    );
  }

  Future<void> upsertUser(Map<String, dynamic> user) async {
    final db = await database;
    await db.insert(
      'users',
      {
        'id': user['id'],
        'phone': user['phone'],
        'shop_name': user['shop_name'] ?? user['name'],
        'settings': user['settings']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getUser() async {
    final db = await database;
    final rows = await db.query('users', limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<int> insertCustomer({
    required String name,
    String? phone,
    double openingBalance = 0,
  }) async {
    final db = await database;
    return db.insert('customers', {
      'name': name,
      'phone': phone,
      'opening_balance': openingBalance,
      'created_at': DateTime.now().toIso8601String(),
      'is_archived': 0,
      'synced': 0,
    });
  }

  Future<void> updateCustomerServerInfo({
    required int id,
    required int serverId,
    bool synced = true,
  }) async {
    final db = await database;
    await db.update(
      'customers',
      {
        'server_id': serverId,
        'synced': synced ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> listCustomersWithBalance() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT c.*, 
        COALESCE((SELECT SUM(amount) FROM transactions t WHERE t.customer_id = c.id AND t.type = 'CREDIT'), 0) AS credit,
        COALESCE((SELECT SUM(amount) FROM transactions t WHERE t.customer_id = c.id AND t.type = 'DEBIT'), 0) AS debit
      FROM customers c
      WHERE c.is_archived = 0
      ORDER BY c.created_at DESC
    ''');

    return rows.map((row) {
      final opening = (row['opening_balance'] as num?)?.toDouble() ?? 0;
      final credit = (row['credit'] as num?)?.toDouble() ?? 0;
      final debit = (row['debit'] as num?)?.toDouble() ?? 0;
      final balance = opening + credit - debit;
      return {
        ...row,
        'balance': balance,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listTransactions(int customerId) async {
    final db = await database;
    return db.query(
      'transactions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> listUnsyncedTransactions() async {
    final db = await database;
    return db.query(
      'transactions',
      where: 'synced = 0',
      orderBy: 'created_at DESC',
    );
  }

  Future<int> insertTransaction({
    required int customerId,
    required double amount,
    required String type,
    String? note,
    DateTime? createdAt,
  }) async {
    final db = await database;
    return db.insert('transactions', {
      'customer_id': customerId,
      'amount': amount,
      'type': type,
      'note': note,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'synced': 0,
    });
  }

  Future<void> updateTransactionServerInfo({
    required int id,
    required int serverId,
    bool synced = true,
  }) async {
    final db = await database;
    await db.update(
      'transactions',
      {
        'server_id': serverId,
        'synced': synced ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateTransaction({
    required int id,
    required double amount,
    required String type,
    String? note,
    DateTime? createdAt,
  }) async {
    final db = await database;
    return db.update(
      'transactions',
      {
        'amount': amount,
        'type': type,
        'note': note,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        'synced': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertCustomersFromServer(
      List<Map<String, dynamic>> customers) async {
    final db = await database;
    final batch = db.batch();
    for (final c in customers) {
      batch.insert(
        'customers',
        {
          'server_id': c['id'],
          'name': c['name'],
          'phone': c['phone'],
          'opening_balance': (c['opening_balance'] as num?)?.toDouble() ?? 0,
          'is_archived': (c['is_archived'] ?? false) == true ? 1 : 0,
          'created_at': (c['created_at'] ?? DateTime.now().toIso8601String())
              .toString(),
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.update(
        'customers',
        {
          'name': c['name'],
          'phone': c['phone'],
          'opening_balance': (c['opening_balance'] as num?)?.toDouble() ?? 0,
          'is_archived': (c['is_archived'] ?? false) == true ? 1 : 0,
          'synced': 1,
        },
        where: 'server_id = ?',
        whereArgs: [c['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertTransactionsFromServer(
      List<Map<String, dynamic>> transactions) async {
    final db = await database;
    final customers = await db.query('customers');
    final serverIdToLocalId = <int, int>{};
    for (final c in customers) {
      final serverId = c['server_id'] as int?;
      if (serverId != null) {
        serverIdToLocalId[serverId] = c['id'] as int;
      }
    }

    final batch = db.batch();
    for (final t in transactions) {
      final serverCustomerId = t['customer_id'] as int?;
      final localCustomerId =
          serverCustomerId != null ? serverIdToLocalId[serverCustomerId] : null;
      if (localCustomerId == null) continue;

      batch.insert(
        'transactions',
        {
          'server_id': t['id'],
          'customer_id': localCustomerId,
          'amount': (t['amount'] as num?)?.toDouble() ?? 0,
          'type': t['type'],
          'note': t['note'],
          'created_at': (t['created_at'] ?? DateTime.now().toIso8601String())
              .toString(),
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.update(
        'transactions',
        {
          'amount': (t['amount'] as num?)?.toDouble() ?? 0,
          'type': t['type'],
          'note': t['note'],
          'created_at': (t['created_at'] ?? DateTime.now().toIso8601String())
              .toString(),
          'synced': 1,
        },
        where: 'server_id = ?',
        whereArgs: [t['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, double>> reportTotals({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN type = 'CREDIT' THEN amount END), 0) AS total_credit,
        COALESCE(SUM(CASE WHEN type = 'DEBIT' THEN amount END), 0) AS total_debit
      FROM transactions
      WHERE created_at >= ? AND created_at <= ?
    ''', [from.toIso8601String(), to.toIso8601String()]);

    final row = rows.isNotEmpty ? rows.first : {};
    final credit = (row['total_credit'] as num?)?.toDouble() ?? 0;
    final debit = (row['total_debit'] as num?)?.toDouble() ?? 0;
    return {
      'credit': credit,
      'debit': debit,
      'net': credit - debit,
    };
  }
}
