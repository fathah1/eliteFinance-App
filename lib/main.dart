import 'package:flutter/material.dart';
import 'api.dart';
import 'db.dart';
import 'sync.dart';

void main() {
  runApp(const LedgerApp());
}

class LedgerApp extends StatelessWidget {
  const LedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ledger App',
      theme: ThemeData(useMaterial3: true),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Db.instance.database;
    final token = await Api.getToken();
    final user = await Api.getUser();
    if (user != null) {
      await Db.instance.upsertUser(user);
    }

    if (!mounted) return;
    if (token != null && token.isNotEmpty) {
      await SyncService.instance.syncAll();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store, size: 64),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    if (_emailController.text.isEmpty && _phoneController.text.isEmpty) {
      setState(() {
        _error = 'Please enter email or phone.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await Api.login(
        email: _emailController.text.isNotEmpty ? _emailController.text : null,
        phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
        password: _passwordController.text,
      );

      if (data['user'] is Map<String, dynamic>) {
        await Db.instance.upsertUser(data['user'] as Map<String, dynamic>);
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login / OTP')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'OTP / Password'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Login'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      );
                    },
              child: const Text('Create an account'),
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _register() async {
    if (_emailController.text.isEmpty && _phoneController.text.isEmpty) {
      setState(() {
        _error = 'Please enter email or phone.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await Api.register(
        name: _nameController.text,
        email: _emailController.text.isNotEmpty ? _emailController.text : null,
        phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
        password: _passwordController.text,
      );

      if (data['user'] is Map<String, dynamic>) {
        await Db.instance.upsertUser(data['user'] as Map<String, dynamic>);
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _loading ? null : _register,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    SyncService.instance.syncAll().then((_) => _loadCustomers());
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _loading = true;
    });
    final data = await Db.instance.listCustomersWithBalance();
    if (!mounted) return;
    setState(() {
      _customers = data;
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    if (_query.isEmpty) {
      _filtered = _customers;
      return;
    }
    final q = _query.toLowerCase();
    _filtered = _customers.where((c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      final phone = (c['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  Color _balanceColor(double balance) {
    if (balance > 0) return Colors.red;
    if (balance < 0) return Colors.green;
    return Colors.grey;
  }

  String _balanceLabel(double balance) {
    final value = balance.abs().toStringAsFixed(2);
    return balance == 0 ? '0.00' : (balance > 0 ? '+$value' : '-$value');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCustomers,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              await SyncService.instance.syncAll();
              _loadCustomers();
            },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddCustomerScreen()),
          );
          _loadCustomers();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search customer',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                setState(() {
                  _query = v.trim();
                  _applyFilter();
                });
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('No customers yet.'))
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final c = _filtered[index];
                          final balance =
                              (c['balance'] as num?)?.toDouble() ?? 0;
                          return ListTile(
                            title: Text((c['name'] ?? '').toString()),
                            subtitle: Text((c['phone'] ?? '').toString()),
                            trailing: Text(
                              _balanceLabel(balance),
                              style: TextStyle(
                                color: _balanceColor(balance),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CustomerLedgerScreen(
                                    customer: c,
                                  ),
                                ),
                              ).then((_) => _loadCustomers());
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _openingController = TextEditingController();
  String? _error;
  bool _loading = false;

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() {
        _error = 'Name is required.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final opening = double.tryParse(_openingController.text.trim()) ?? 0;
    final localId = await Db.instance.insertCustomer(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      openingBalance: opening,
    );
    try {
      final created = await Api.createCustomer(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        openingBalance: opening,
      );
      if (created['id'] != null) {
        await Db.instance.updateCustomerServerInfo(
          id: localId,
          serverId: created['id'] as int,
        );
      }
    } catch (_) {
      // Offline or server error: keep local record for later sync.
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Customer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: _openingController,
              decoration:
                  const InputDecoration(labelText: 'Opening balance (optional)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerLedgerScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerLedgerScreen({super.key, required this.customer});

  @override
  State<CustomerLedgerScreen> createState() => _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends State<CustomerLedgerScreen> {
  List<Map<String, dynamic>> _transactions = [];
  double _balance = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final tx = await Db.instance.listTransactions(widget.customer['id'] as int);
    final credit = tx
        .where((t) => t['type'] == 'CREDIT')
        .fold<double>(0, (sum, t) => sum + (t['amount'] as num).toDouble());
    final debit = tx
        .where((t) => t['type'] == 'DEBIT')
        .fold<double>(0, (sum, t) => sum + (t['amount'] as num).toDouble());
    final opening =
        (widget.customer['opening_balance'] as num?)?.toDouble() ?? 0;
    final balance = opening + credit - debit;

    if (!mounted) return;
    setState(() {
      _transactions = tx;
      _balance = balance;
      _loading = false;
    });
  }

  Color _balanceColor(double balance) {
    if (balance > 0) return Colors.red;
    if (balance < 0) return Colors.green;
    return Colors.grey;
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _deleteTx(int id) async {
    final tx = _transactions.firstWhere((t) => t['id'] == id);
    final serverId = tx['server_id'] as int?;
    await Db.instance.deleteTransaction(id);
    if (serverId != null) {
      try {
        await Api.deleteTransaction(serverId);
      } catch (_) {
        // Ignore network errors for now.
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.customer['name'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.sms),
            onPressed: () {
              final amount = _balance.abs().toStringAsFixed(2);
              final message =
                  'Hi, you have ₹$amount pending with ${name.toString()}';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Reminder: $message')),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddEntryScreen(customerId: widget.customer['id']),
            ),
          );
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey.shade200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Balance',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        _balance.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _balanceColor(_balance),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _transactions.isEmpty
                      ? const Center(child: Text('No entries yet.'))
                      : ListView.separated(
                          itemCount: _transactions.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final t = _transactions[index];
                            final amount =
                                (t['amount'] as num).toDouble().toStringAsFixed(2);
                            final type = t['type'] as String;
                            final color =
                                type == 'CREDIT' ? Colors.red : Colors.green;
                            return ListTile(
                              title: Text((t['note'] ?? '').toString()),
                              subtitle: Text(_formatDate(t['created_at'] as String)),
                              trailing: Text(
                                '${type == 'CREDIT' ? '+' : '-'}$amount',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AddEntryScreen(
                                      customerId: widget.customer['id'],
                                      transaction: t,
                                    ),
                                  ),
                                );
                                _load();
                              },
                              onLongPress: () => _deleteTx(t['id'] as int),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class AddEntryScreen extends StatefulWidget {
  final int customerId;
  final Map<String, dynamic>? transaction;
  const AddEntryScreen({
    super.key,
    required this.customerId,
    this.transaction,
  });

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _type = 'CREDIT';
  DateTime _date = DateTime.now();
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    if (t != null) {
      _amountController.text = (t['amount'] ?? '').toString();
      _noteController.text = (t['note'] ?? '').toString();
      _type = (t['type'] ?? 'CREDIT').toString();
      final raw = t['created_at']?.toString();
      final parsed = raw != null ? DateTime.tryParse(raw) : null;
      if (parsed != null) _date = parsed;
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _error = 'Enter a valid amount.';
      });
      return;
    }

    final createdAt = _date.toIso8601String();
    if (widget.transaction == null) {
      final localId = await Db.instance.insertTransaction(
        customerId: widget.customerId,
        amount: amount,
        type: _type,
        note: _noteController.text.trim(),
        createdAt: _date,
      );
      try {
        // Map local customer to server customer id if available.
        // The customer list provides server_id on the customer record.
        // We try to look up the customer from Db when syncing.
        final all = await Db.instance.listCustomersWithBalance();
        final match = all.firstWhere(
          (c) => c['id'] == widget.customerId,
          orElse: () => {},
        );
        final serverCustomerId = match['server_id'] as int?;
        if (serverCustomerId != null) {
          final created = await Api.createTransaction(
            customerId: serverCustomerId,
            amount: amount,
            type: _type,
            note: _noteController.text.trim(),
            createdAt: createdAt,
          );
          if (created['id'] != null) {
            await Db.instance.updateTransactionServerInfo(
              id: localId,
              serverId: created['id'] as int,
            );
          }
        }
      } catch (_) {
        // Offline or server error: keep local record for later sync.
      }
    } else {
      await Db.instance.updateTransaction(
        id: widget.transaction!['id'] as int,
        amount: amount,
        type: _type,
        note: _noteController.text.trim(),
        createdAt: _date,
      );
      final serverId = widget.transaction!['server_id'] as int?;
      if (serverId != null) {
        try {
          await Api.updateTransaction(
            transactionId: serverId,
            amount: amount,
            type: _type,
            note: _noteController.text.trim(),
            createdAt: createdAt,
          );
        } catch (_) {
          // Ignore network errors for now.
        }
      }
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.transaction != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Entry' : 'Add Entry')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'CREDIT', child: Text('Credit (owes you)')),
                DropdownMenuItem(value: 'DEBIT', child: Text('Debit (you owe)')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _type = v;
                });
              },
              decoration: const InputDecoration(labelText: 'Type'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Date: ${_date.toLocal().toString().split(' ').first}',
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _date = picked;
                      });
                    }
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _save,
              child: Text(isEdit ? 'Update' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  bool _loading = true;
  double _credit = 0;
  double _debit = 0;
  double _net = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final totals = await Db.instance.reportTotals(from: _from, to: _to);
    if (!mounted) return;
    setState(() {
      _credit = totals['credit'] ?? 0;
      _debit = totals['debit'] ?? 0;
      _net = totals['net'] ?? 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('From: ${_from.toLocal().toString().split(' ').first}'),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _from,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _from = picked;
                      });
                      _load();
                    }
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text('To:   ${_to.toLocal().toString().split(' ').first}'),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _to,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _to = picked;
                      });
                      _load();
                    }
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _loading
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      ListTile(
                        title: const Text('Total Credit'),
                        trailing: Text(_credit.toStringAsFixed(2)),
                      ),
                      ListTile(
                        title: const Text('Total Debit'),
                        trailing: Text(_debit.toStringAsFixed(2)),
                      ),
                      ListTile(
                        title: const Text('Net Balance'),
                        trailing: Text(_net.toStringAsFixed(2)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Export coming soon.'),
                            ),
                          );
                        },
                        child: const Text('Export'),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await Db.instance.getUser();
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await Api.clearToken();
    await Api.clearUser();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  title: const Text('User'),
                  subtitle: Text(
                    (_user?['shop_name'] ?? _user?['phone'] ?? 'Unknown')
                        .toString(),
                  ),
                ),
                const Divider(),
                const ListTile(
                  title: Text('Backup'),
                  subtitle: Text('Manual backup and sync coming soon'),
                ),
                const ListTile(
                  title: Text('Language'),
                  subtitle: Text('English'),
                ),
                const ListTile(
                  title: Text('Currency'),
                  subtitle: Text('INR (₹)'),
                ),
                const ListTile(
                  title: Text('App Lock'),
                  subtitle: Text('Disabled'),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Logout'),
                  onTap: _logout,
                ),
              ],
            ),
    );
  }
}
