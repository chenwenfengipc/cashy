import 'dart:convert';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart' as p;
import '../models/transaction.dart';
import '../models/settings.dart';
import '../utils/rate_table.dart';

/// Singleton SQLite database helper.
/// Creates / opens the app database and provides CRUD helpers.
class DatabaseHelper {
  static const _dbName = 'cashy.db';
  static const _dbVersion = 2;

  // --- table names ---
  static const tTransactions = 'transactions';
  static const tCategories = 'categories';
  static const tSettings = 'settings';
  static const tExchangeRates = 'exchange_rates';

  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;
  Future<Database> get db async => _db ??= await _init();

  // ──────────────────────────────────────────────────────────────
  //  Schema
  // ──────────────────────────────────────────────────────────────

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );
  }

  /// Schema migrations. Bump [_dbVersion] and add one `if (oldVersion < N)`
  /// block per version here — each block applies only the change introduced
  /// in that version, so a device jumping several versions at once (e.g.
  /// v1 → v3) applies all of them in order without losing data.
  ///
  /// Example for the next schema change:
  /// ```dart
  /// if (oldVersion < 2) {
  ///   await db.execute('ALTER TABLE $tTransactions ADD COLUMN tags TEXT');
  /// }
  /// ```
  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE $tExchangeRates ADD COLUMN is_manual INTEGER NOT NULL DEFAULT 0');
      // v1 couldn't tell built-in estimates from the user's own edits, so
      // treat any row that differs from the seed values as the user's.
      for (final row in await db.query(tExchangeRates)) {
        final from = row['from_currency'] as String;
        final to = row['to_currency'] as String;
        final rate = (row['rate'] as num).toDouble();
        final seed = _defaultRates.where((d) => d['from'] == from && d['to'] == to);
        final edited =
            seed.isEmpty || ((seed.first['rate'] as double) - rate).abs() > 1e-9;
        if (edited) {
          await db.update(tExchangeRates, {'is_manual': 1},
              where: 'from_currency = ? AND to_currency = ?',
              whereArgs: [from, to]);
        }
      }
    }
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tTransactions (
        id           TEXT PRIMARY KEY,
        type         TEXT NOT NULL,
        amount       REAL NOT NULL,
        currency     TEXT NOT NULL DEFAULT 'MYR',
        amount_in_base REAL NOT NULL,
        category_name TEXT,
        note         TEXT,
        created_at   TEXT NOT NULL,
        updated_at   TEXT NOT NULL,
        raw_voice    TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tCategories (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT NOT NULL,
        type        TEXT NOT NULL,
        icon        TEXT DEFAULT '📦',
        keywords_en TEXT DEFAULT '',
        keywords_zh TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE $tSettings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tExchangeRates (
        from_currency TEXT NOT NULL,
        to_currency   TEXT NOT NULL,
        rate          REAL NOT NULL,
        is_manual     INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (from_currency, to_currency)
      )
    ''');

    // Seed default categories + default settings.
    await _seedCategories(db);
    await _seedSettings(db);
    await _seedExchangeRates(db);
  }

  // ──────────────────────────────────────────────────────────────
  //  Seeds
  // ──────────────────────────────────────────────────────────────

  Future<void> _seedCategories(Database db) async {
    final defaults = [
      // Expense
      _cat('Food', 'expense', '🍔', 'lunch,dinner,breakfast,grocery,meal,restaurant,eat,food,coffee,tea,snack',
          '吃饭,午餐,晚餐,早餐,买菜,餐厅,外卖,零食,咖啡,茶,水果'),
      _cat('Transport', 'expense', '🚗', 'petrol,gas,grab,taxi,bus,train,parking,transport,fare,ride,uber,grabcar',
          '油,汽油,打车,出租车,巴士,地铁,停车,交通,车费,电召车,gra'),
      _cat('Bills & Utilities', 'expense', '⚡', 'electricity,water,internet,phone,rent,bill,utility,wifi,streaming',
          '电费,水费,网费,电话费,房租,账单,物业费,水电'),
      _cat('Shopping', 'expense', '🛍️', 'bought,clothes,shoes,bags,online,shop,mall,amazon,shopee,lazada',
          '买东西,衣服,鞋子,包包,网购,淘宝,shopee,lazada'),
      _cat('Entertainment', 'expense', '🎬', 'movie,ticket,game,netflix,spotify,concert,sport,hobby',
          '电影,门票,游戏,娱乐,唱歌,旅游,运动'),
      _cat('Health', 'expense', '🏥', 'doctor,clinic,hospital,medicine,pharmacy,dental,insurance,medical',
          '看医生,医院,药,诊所,牙医,体检,保险'),
      _cat('Education', 'expense', '📚', 'course,book,tuition,school,university,class,training,online course',
          '书,学费,课程,培训,补习,学校,报名'),
      _cat('Others', 'expense', '📦', '', ''),
      // Income
      _cat('Salary', 'income', '💰', 'salary,wage,paycheck,bonus,income,payment,pay',
          '工资,薪水,奖金,收入,月薪,发工资,工钱'),
      _cat('Freelance', 'income', '💼', 'freelance,project,side,hustle,gig,contract',
          '自由职业,项目,外快,兼职,副业'),
      _cat('Gift', 'income', '🎁', 'gift,angpao,hongbao,received,red packet',
          '红包,礼物,赠予,收到'),
      _cat('Others', 'income', '📦', '', ''),
    ];
    for (final c in defaults) {
      await db.insert(tCategories, c);
    }
  }

  Map<String, dynamic> _cat(String name, String type, String icon, String en, String zh) => {
        'name': name,
        'type': type,
        'icon': icon,
        'keywords_en': en,
        'keywords_zh': zh,
      };

  Future<void> _seedSettings(Database db) async {
    await db.insert(tSettings, {'key': 'app_settings', 'value': jsonEncode({
      'base_currency': 'SGD',
      'default_language': 'en',
      'monthly_budget_limit': 0,
    })});
  }

  // Built-in starting estimates, replaced by the monthly download (or by the
  // user's own edits). Any pair not listed is derived through MYR.
  // Maps are used instead of record tuples for web compatibility.
  static const _defaultRates = <Map<String, Object>>[
    {'from': 'MYR', 'to': 'USD', 'rate': 0.21},
    {'from': 'MYR', 'to': 'CNY', 'rate': 1.55},
    {'from': 'MYR', 'to': 'SGD', 'rate': 0.29},
    {'from': 'MYR', 'to': 'IDR', 'rate': 3450.0},
    {'from': 'MYR', 'to': 'JPY', 'rate': 32.5},
    {'from': 'MYR', 'to': 'THB', 'rate': 7.7},
    {'from': 'MYR', 'to': 'EUR', 'rate': 0.20},
    {'from': 'USD', 'to': 'MYR', 'rate': 4.70},
    {'from': 'CNY', 'to': 'MYR', 'rate': 0.65},
    {'from': 'SGD', 'to': 'MYR', 'rate': 3.45},
    {'from': 'JPY', 'to': 'MYR', 'rate': 0.031},
  ];

  Future<void> _seedExchangeRates(Database db) async {
    for (final row in _defaultRates) {
      await db.insert(tExchangeRates, {
        'from_currency': row['from'],
        'to_currency': row['to'],
        'rate': row['rate'],
      });
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  Transactions CRUD
  // ──────────────────────────────────────────────────────────────

  Future<int> insertTransaction(Transaction tx) async {
    final d = await db;
    return d.insert(tTransactions, tx.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Transaction>> getTransactions({int? year, int? month}) async {
    final d = await db;
    String? where;
    List<dynamic>? whereArgs;
    if (year != null && month != null) {
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month + 1, 1);
      where = 'created_at >= ? AND created_at < ?';
      whereArgs = [start.toIso8601String(), end.toIso8601String()];
    }
    final rows = await d.query(tTransactions,
        where: where,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC');
    return rows.map((r) => Transaction.fromMap(r)).toList();
  }

  Future<Transaction?> getTransaction(String id) async {
    final d = await db;
    final rows = await d.query(tTransactions, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Transaction.fromMap(rows.first);
  }

  /// All transactions regardless of month — used for full-data backup export.
  Future<List<Transaction>> getAllTransactions() async {
    final d = await db;
    final rows = await d.query(tTransactions, orderBy: 'created_at DESC');
    return rows.map((r) => Transaction.fromMap(r)).toList();
  }

  Future<int> updateTransaction(Transaction tx) async {
    final d = await db;
    return d.update(tTransactions, tx.toMap(),
        where: 'id = ?', whereArgs: [tx.id]);
  }

  Future<int> deleteTransaction(String id) async {
    final d = await db;
    return d.delete(tTransactions, where: 'id = ?', whereArgs: [id]);
  }

  Future<double> totalIncome({int? year, int? month}) =>
      _sum('income', year, month);

  Future<double> totalExpense({int? year, int? month}) =>
      _sum('expense', year, month);

  Future<double> _sum(String type, int? year, int? month) async {
    final d = await db;
    String? where = 'type = ?';
    List<dynamic> args = [type];
    if (year != null && month != null) {
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month + 1, 1);
      where += ' AND created_at >= ? AND created_at < ?';
      args.addAll([start.toIso8601String(), end.toIso8601String()]);
    }
    final result = await d.rawQuery(
        'SELECT COALESCE(SUM(amount_in_base), 0) AS total FROM $tTransactions WHERE $where',
        args);
    return (result.first['total'] as num).toDouble();
  }

  Future<Map<String, double>> categoryBreakdown(
      TransactionType type, int year, int month) async {
    final d = await db;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    final rows = await d.rawQuery('''
      SELECT COALESCE(category_name, 'Uncategorized') AS category_name,
             COALESCE(SUM(amount_in_base), 0) AS total
      FROM $tTransactions
      WHERE type = ? AND created_at >= ? AND created_at < ?
      GROUP BY category_name
      ORDER BY total DESC
    ''', [type.name, start.toIso8601String(), end.toIso8601String()]);
    return {for (final r in rows) r['category_name'] as String: (r['total'] as num).toDouble()};
  }

  // ──────────────────────────────────────────────────────────────
  //  Categories CRUD
  // ──────────────────────────────────────────────────────────────

  Future<List<TransactionCategory>> getCategories({TransactionType? type}) async {
    final d = await db;
    final rows = type != null
        ? await d.query(tCategories, where: 'type = ?', whereArgs: [type.name])
        : await d.query(tCategories);
    return rows.map((r) => TransactionCategory.fromMap(r)).toList();
  }

  Future<int> insertCategory(TransactionCategory cat) async {
    final d = await db;
    return d.insert(tCategories, cat.toMap());
  }

  Future<int> updateCategory(TransactionCategory cat) async {
    final d = await db;
    return d.update(tCategories, cat.toMap(),
        where: 'id = ?', whereArgs: [cat.id]);
  }

  Future<int> deleteCategory(int id) async {
    final d = await db;
    return d.delete(tCategories, where: 'id = ?', whereArgs: [id]);
  }

  // ──────────────────────────────────────────────────────────────
  //  Settings
  // ──────────────────────────────────────────────────────────────

  Future<AppSettings> getSettings() async {
    final d = await db;
    final rows = await d.query(tSettings, where: 'key = ?', whereArgs: ['app_settings']);
    if (rows.isEmpty) return const AppSettings();
    return AppSettings.fromMap(jsonDecode(rows.first['value'] as String) as Map<String, dynamic>);
  }

  Future<void> saveSettings(AppSettings s) async {
    final d = await db;
    await d.insert(tSettings, {
      'key': 'app_settings',
      'value': jsonEncode(s.toMap()..remove('key')),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ──────────────────────────────────────────────────────────────
  //  Exchange Rates
  // ──────────────────────────────────────────────────────────────

  Future<List<ExchangeRate>> getExchangeRates() async {
    final d = await db;
    final rows = await d.query(tExchangeRates);
    return rows.map((r) => ExchangeRate.fromMap(r)).toList();
  }

  Future<void> saveExchangeRate(ExchangeRate r) async {
    final d = await db;
    await d.insert(tExchangeRates, r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteExchangeRate(String from, String to) async {
    final d = await db;
    await d.delete(tExchangeRates,
        where: 'from_currency = ? AND to_currency = ?', whereArgs: [from, to]);
  }

  /// Swap every non-manual rate for freshly downloaded [rates]. Rates the
  /// user typed in by hand are kept, and win over a downloaded row for the
  /// same pair.
  Future<void> replaceAutoRates(List<ExchangeRate> rates) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete(tExchangeRates, where: 'is_manual = 0');
      for (final r in rates) {
        await txn.insert(tExchangeRates, r.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  /// Get monthly income/expense totals for the last [count] months (including current).
  Future<List<MonthlyTotal>> getMonthlyTotals(int count) async {
    final d = await db;
    final now = DateTime.now();
    final results = <MonthlyTotal>[];

    for (int i = count - 1; i >= 0; i--) {
      // Zero-based month index relative to year 0, so year/month wraps
      // correctly however many years back [i] pushes us.
      final monthIndex = now.year * 12 + (now.month - 1) - i;
      final y = monthIndex ~/ 12;
      final month = monthIndex % 12 + 1;

      final start = DateTime(y, month, 1);
      final end = DateTime(y, month + 1, 1);

      final rows = await d.rawQuery('''
        SELECT type, COALESCE(SUM(amount_in_base), 0) AS total
        FROM $tTransactions
        WHERE created_at >= ? AND created_at < ?
        GROUP BY type
      ''', [start.toIso8601String(), end.toIso8601String()]);

      double income = 0, expense = 0;
      for (final r in rows) {
        if (r['type'] == 'income') income = (r['total'] as num).toDouble();
        if (r['type'] == 'expense') expense = (r['total'] as num).toDouble();
      }
      results.add(MonthlyTotal(year: y, month: month, income: income, expense: expense));
    }
    return results;
  }
  Future<double> convertCurrency(
      double amount, String fromCurrency, String toCurrency) async {
    if (fromCurrency == toCurrency) return amount;
    final rate =
        RateTable(await getExchangeRates()).rate(fromCurrency, toCurrency);
    // No path between the two currencies at all: keep the amount as typed.
    return rate == null ? amount : amount * rate;
  }
}

/// Monthly aggregation used by the trend chart.
class MonthlyTotal {
  final int year;
  final int month;
  final double income;
  final double expense;

  const MonthlyTotal({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });

  double get balance => income - expense;

  String get label {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month];
  }
}
