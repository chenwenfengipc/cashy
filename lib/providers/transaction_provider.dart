import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart';

/// Manages the list of transactions, monthly aggregation, and CRUD.
class TransactionProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  List<Transaction> _transactions = [];
  TransactionFilter _filter = TransactionFilter.currentMonth();
  bool _loaded = false;

  // Cached aggregates.
  double _totalIncome = 0;
  double _totalExpense = 0;
  Map<String, double> _categoryBreakdown = {};
  List<MonthlyTotal> _monthlyTrend = [];

  List<Transaction> get transactions => _transactions;
  TransactionFilter get filter => _filter;
  bool get isLoaded => _loaded;

  double get totalIncome => _totalIncome;
  double get totalExpense => _totalExpense;
  double get balance => _totalIncome - _totalExpense;
  Map<String, double> get categoryBreakdown => _categoryBreakdown;
  List<MonthlyTotal> get monthlyTrend => _monthlyTrend;

  // ── Load / Refresh ───────────────────────────────────────────

  /// Load transactions for the current filter period.
  Future<void> load() async {
    await _loadMonth(_filter.year, _filter.month);
    await _loadMonthlyTrend();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _loadMonth(int year, int month) async {
    _transactions = await _db.getTransactions(year: year, month: month);
    _totalIncome = await _db.totalIncome(year: year, month: month);
    _totalExpense = await _db.totalExpense(year: year, month: month);
    _categoryBreakdown = await _db.categoryBreakdown(
      TransactionType.expense, year, month);
  }

  Future<void> _loadMonthlyTrend() async {
    _monthlyTrend = await _db.getMonthlyTotals(6);
  }

  /// Change month filter.
  Future<void> setFilter(TransactionFilter newFilter) async {
    _filter = newFilter;
    await _loadMonth(_filter.year, _filter.month);
    await _loadMonthlyTrend();
    notifyListeners();
  }

  /// Navigate to previous month.
  Future<void> previousMonth() async {
    final m = _filter.month - 1;
    final y = m < 1 ? _filter.year - 1 : _filter.year;
    final month = m < 1 ? 12 : m;
    await setFilter(TransactionFilter(year: y, month: month));
  }

  /// Navigate to next month.
  Future<void> nextMonth() async {
    final m = _filter.month + 1;
    final y = m > 12 ? _filter.year + 1 : _filter.year;
    final month = m > 12 ? 1 : m;
    await setFilter(TransactionFilter(year: y, month: month));
  }

  // ── CRUD ────────────────────────────────────────────────────

  /// Add a new transaction (from voice or manual).
  Future<void> addTransaction(ParsedTransaction parsed,
      {required double amountInBase}) async {
    final tx = Transaction(
      id: _uuid.v4(),
      type: parsed.type,
      amount: parsed.amount,
      currency: parsed.currency,
      amountInBase: amountInBase,
      categoryName: parsed.categoryName,
      note: parsed.note,
      createdAt: parsed.date ?? DateTime.now(),
      updatedAt: DateTime.now(),
      rawVoice: parsed.rawText,
    );
    await _db.insertTransaction(tx);
    // Reload current month to reflect the change.
    await _loadMonth(_filter.year, _filter.month);
    await _loadMonthlyTrend();
    notifyListeners();
  }

  /// Update an existing transaction.
  Future<void> updateTransaction(Transaction tx) async {
    await _db.updateTransaction(tx);
    await _loadMonth(_filter.year, _filter.month);
    await _loadMonthlyTrend();
    notifyListeners();
  }

  /// Delete a transaction.
  Future<void> deleteTransaction(String id) async {
    await _db.deleteTransaction(id);
    await _loadMonth(_filter.year, _filter.month);
    await _loadMonthlyTrend();
    notifyListeners();
  }

  // ── Categories ──────────────────────────────────────────────

  Future<List<TransactionCategory>> getCategories({TransactionType? type}) =>
      _db.getCategories(type: type);

  Future<void> addCategory(TransactionCategory cat) async {
    await _db.insertCategory(cat);
    notifyListeners();
  }

  Future<void> updateCategory(TransactionCategory cat) async {
    await _db.updateCategory(cat);
    notifyListeners();
  }
}

/// Simple filter: a specific (year, month) combination.
class TransactionFilter {
  final int year;
  final int month;

  const TransactionFilter({required this.year, required this.month});

  factory TransactionFilter.currentMonth() {
    final now = DateTime.now();
    return TransactionFilter(year: now.year, month: now.month);
  }

  String get label {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[month]} $year';
  }
}
