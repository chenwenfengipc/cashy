/// Base currency config — user picks one at setup.
enum BaseCurrency {
  myr('MYR', 'RM'),
  usd('USD', r'$'),
  cny('CNY', '¥'),
  sgd('SGD', 'S\$'),
  idr('IDR', 'Rp'),
  jpy('JPY', '¥'),
  thb('THB', '฿'),
  eur('EUR', '€');

  final String code;
  final String symbol;

  const BaseCurrency(this.code, this.symbol);

  static BaseCurrency fromCode(String code) =>
      BaseCurrency.values.firstWhere((c) => c.code == code, orElse: () => sgd);

  String get displayName => '$symbol ($code)';
}

/// Category: user-defined, with language keywords for NLU matching.
class TransactionCategory {
  final int? id;
  final String name; // e.g. "Food"
  final TransactionType type;
  final String icon; // emoji
  final List<String> keywordsEn; // e.g. ["lunch","dinner","grocery"]
  final List<String> keywordsZh; // e.g. ["午餐","晚餐","买菜"]

  const TransactionCategory({
    this.id,
    required this.name,
    required this.type,
    this.icon = '📦',
    this.keywordsEn = const [],
    this.keywordsZh = const [],
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'type': type.name,
        'icon': icon,
        'keywords_en': keywordsEn.join(','),
        'keywords_zh': keywordsZh.join(','),
      };

  factory TransactionCategory.fromMap(Map<String, dynamic> m) =>
      TransactionCategory(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: TransactionType.values.byName(m['type'] as String),
        icon: m['icon'] as String? ?? '📦',
        keywordsEn: ((m['keywords_en'] as String?) ?? '').split(',').where((e) => e.isNotEmpty).toList(),
        keywordsZh: ((m['keywords_zh'] as String?) ?? '').split(',').where((e) => e.isNotEmpty).toList(),
      );

  TransactionCategory copyWith({
    int? id,
    String? name,
    TransactionType? type,
    String? icon,
    List<String>? keywordsEn,
    List<String>? keywordsZh,
  }) =>
      TransactionCategory(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        icon: icon ?? this.icon,
        keywordsEn: keywordsEn ?? this.keywordsEn,
        keywordsZh: keywordsZh ?? this.keywordsZh,
      );
}

/// A single income or expense record.
class Transaction {
  final String id;
  final TransactionType type; // expense or income
  final double amount;
  final String currency; // e.g. "SGD"
  final double amountInBase; // converted to user's base currency
  final String? categoryName;
  final String? note;
  final DateTime createdAt; // user-specified or default now
  final DateTime updatedAt;
  final String? rawVoice; // original transcribed text

  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    this.currency = 'SGD',
    required this.amountInBase,
    this.categoryName,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.rawVoice,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'currency': currency,
        'amount_in_base': amountInBase,
        'category_name': categoryName,
        'note': note,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'raw_voice': rawVoice,
      };

  factory Transaction.fromMap(Map<String, dynamic> m) => Transaction(
        id: m['id'] as String,
        type: TransactionType.values.byName(m['type'] as String),
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'] as String? ?? 'SGD',
        amountInBase: (m['amount_in_base'] as num).toDouble(),
        categoryName: m['category_name'] as String?,
        note: m['note'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
        rawVoice: m['raw_voice'] as String?,
      );

  Transaction copyWith({
    String? id,
    TransactionType? type,
    double? amount,
    String? currency,
    double? amountInBase,
    String? categoryName,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? rawVoice,
  }) =>
      Transaction(
        id: id ?? this.id,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        amountInBase: amountInBase ?? this.amountInBase,
        categoryName: categoryName ?? this.categoryName,
        note: note ?? this.note,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        rawVoice: rawVoice ?? this.rawVoice,
      );

  /// User‑friendly display label for the month this belongs to.
  String get monthLabel {
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[createdAt.month]} ${createdAt.year}';
  }
}

/// Supported transaction types.
enum TransactionType { expense, income }

/// Result returned by the NLU pipeline — always the same shape
/// regardless of whether PatternExtractor or TinyBERT produced it.
class ParsedTransaction {
  final TransactionType type;
  final double amount;
  final String currency;
  final String? categoryName;
  final String? note;
  final DateTime? date; // parsed date, null → today
  final double confidence; // 0.0 – 1.0
  final String? rawText; // original transcript

  const ParsedTransaction({
    required this.type,
    required this.amount,
    this.currency = 'SGD',
    this.categoryName,
    this.note,
    this.date,
    this.confidence = 1.0,
    this.rawText,
  });

  /// Merge with user corrections.
  ParsedTransaction merge({
    TransactionType? type,
    double? amount,
    String? currency,
    String? categoryName,
    String? note,
    DateTime? date,
  }) =>
      ParsedTransaction(
        type: type ?? this.type,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        categoryName: categoryName ?? this.categoryName,
        note: note ?? this.note,
        date: date ?? this.date,
        confidence: confidence,
        rawText: rawText,
      );

  /// Convert to a storable Transaction.
  Transaction toTransaction({required double amountInBase}) => Transaction(
        id: '', // assigned by DB
        type: type,
        amount: amount,
        currency: currency,
        amountInBase: amountInBase,
        categoryName: categoryName,
        note: note,
        createdAt: date ?? DateTime.now(),
        updatedAt: DateTime.now(),
        rawVoice: rawText,
      );
}
