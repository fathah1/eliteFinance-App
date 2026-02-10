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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            username TEXT,
            phone TEXT,
            shop_name TEXT,
            settings TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE businesses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER,
            name TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER,
            business_id INTEGER NOT NULL,
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
            business_id INTEGER NOT NULL,
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
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE users ADD COLUMN username TEXT');
          await db.execute('''
            CREATE TABLE businesses (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              server_id INTEGER,
              name TEXT NOT NULL,
              synced INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute(
              'ALTER TABLE customers ADD COLUMN business_id INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE transactions ADD COLUMN business_id INTEGER NOT NULL DEFAULT 0');
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
        'username': user['username'],
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

  Future<int> insertBusiness({
    required String name,
  }) async {
    final db = await database;
    return db.insert('businesses', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  Future<void> updateBusinessServerInfo({
    required int id,
    required int serverId,
    bool synced = true,
  }) async {
    final db = await database;
    await db.update(
      'businesses',
      {
        'server_id': serverId,
        'synced': synced ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> listBusinesses() async {
    final db = await database;
    return db.query('businesses', orderBy: 'created_at DESC');
  }

  Future<int> insertCustomer({
    required int businessId,
    required String name,
    String? phone,
    double openingBalance = 0,
  }) async {
    final db = await database;
    return db.insert('customers', {
      'business_id': businessId,
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

  Future<List<Map<String, dynamic>>> listCustomersWithBalance({
    required int businessId,
  }) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT c.*, 
        COALESCE((SELECT SUM(amount) FROM transactions t WHERE t.customer_id = c.id AND t.type = 'CREDIT'), 0) AS credit,
        COALESCE((SELECT SUM(amount) FROM transactions t WHERE t.customer_id = c.id AND t.type = 'DEBIT'), 0) AS debit
      FROM customers c
      WHERE c.is_archived = 0 AND c.business_id = ?
      ORDER BY c.created_at DESC
    ''', [businessId]);

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

  Future<List<Map<String, dynamic>>> listUnsyncedTransactions({
    required int businessId,
  }) async {
    final db = await database;
    return db.query(
      'transactions',
      where: 'synced = 0 AND business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at DESC',
    );
  }

  Future<int> insertTransaction({
    required int businessId,
    required int customerId,
    required double amount,
    required String type,
    String? note,
    DateTime? createdAt,
  }) async {
    final db = await database;
    return db.insert('transactions', {
      'business_id': businessId,
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

  Future<Map<String, double>> reportTotals({
    required int businessId,
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN type = 'CREDIT' THEN amount END), 0) AS total_credit,
        COALESCE(SUM(CASE WHEN type = 'DEBIT' THEN amount END), 0) AS total_debit
      FROM transactions
      WHERE business_id = ? AND created_at >= ? AND created_at <= ?
    ''', [businessId, from.toIso8601String(), to.toIso8601String()]);

    final row = rows.isNotEmpty ? rows.first : {};
    final credit = (row['total_credit'] as num?)?.toDouble() ?? 0;
    final debit = (row['total_debit'] as num?)?.toDouble() ?? 0;
    return {
      'credit': credit,
      'debit': debit,
      'net': credit - debit,
    };
  }

  Future<void> upsertBusinessesFromServer(
      List<Map<String, dynamic>> businesses) async {
    final db = await database;
    final existing = await db.query('businesses', columns: ['server_id']);
    final existingServerIds = <int>{};
    for (final row in existing) {
      final id = row['server_id'] as int?;
      if (id != null) existingServerIds.add(id);
    }

    final batch = db.batch();
    for (final b in businesses) {
      final serverId = b['id'] as int?;
      if (serverId != null && !existingServerIds.contains(serverId)) {
        batch.insert(
          'businesses',
          {
            'server_id': serverId,
            'name': b['name'],
            'created_at': (b['created_at'] ?? DateTime.now().toIso8601String())
                .toString(),
            'synced': 1,
          },
        );
        existingServerIds.add(serverId);
      }
      batch.update(
        'businesses',
        {
          'name': b['name'],
          'synced': 1,
        },
        where: 'server_id = ?',
        whereArgs: [serverId],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertCustomersFromServer(
      List<Map<String, dynamic>> customers) async {
    final db = await database;
    final businesses = await db.query('businesses');
    final serverBizToLocal = <int, int>{};
    for (final b in businesses) {
      final serverId = b['server_id'] as int?;
      if (serverId != null) {
        serverBizToLocal[serverId] = b['id'] as int;
      }
    }

    final batch = db.batch();
    for (final c in customers) {
      final serverBizId = c['business_id'] as int?;
      final localBizId =
          serverBizId != null ? serverBizToLocal[serverBizId] : null;
      if (localBizId == null) continue;

      batch.insert(
        'customers',
        {
          'server_id': c['id'],
          'business_id': localBizId,
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
          'business_id': t['business_id'],
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
}
