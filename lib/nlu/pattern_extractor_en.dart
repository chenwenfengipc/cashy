import '../models/transaction.dart';
import 'nlu_extractor.dart';

/// Helper to hold extracted amount + currency (replaces Dart record tuples
/// which are not supported by the web compiler).
class _AmountResult {
  final double amount;
  final String currency;
  const _AmountResult(this.amount, this.currency);
}

class _NumberRun {
  final String text;
  final int end;
  const _NumberRun(this.text, this.end);
}

/// English pattern-based NLU extractor.
///
/// Handles common phrases like:
///  - "I spent 15 ringgit on lunch at McDonalds"
///  - "received salary 5000 yesterday"
///  - "bought groceries 30 dollars at Jaya Grocer"
///  - "paid electricity bill 150"
///  - "uber 12.50"  (implicit expense + transport)
class PatternExtractorEn extends NluExtractor {
  @override
  String get language => 'en';

  // ── Intent keywords ───────────────────────────────────────────
  static const _expenseVerbs = [
    'spent', 'paid', 'bought', 'cost', 'spend', 'pay', 'buy',
    'purchased', 'purchase', 'ordered', 'order', 'had', 'ate',
    'used', 'charge', 'charged', 'bill',
  ];
  // Note: 'get'/'got' are deliberately excluded — they're too generic and
  // commonly appear in expense phrasing too ("got lunch", "got a haircut").
  static const _incomeVerbs = [
    'received', 'earned', 'receive', 'salary',
    'deposited', 'credited', 'transfer', 'transferred',
  ];

  // ── Currency detection ────────────────────────────────────────
  static const _currencyMap = {
    'rm': 'MYR', 'ringgit': 'MYR', 'myr': 'MYR',
    'usd': 'USD', 'dollar': 'USD', 'dollars': 'USD', r'$': 'USD',
    'sgd': 'SGD', 'singapore dollar': 'SGD',
    'cny': 'CNY', 'yuan': 'CNY', 'rmb': 'CNY', 'renminbi': 'CNY',
    'eur': 'EUR', 'euro': 'EUR', 'euros': 'EUR',
    'jpy': 'JPY', 'yen': 'JPY',
    'idr': 'IDR', 'rupiah': 'IDR', 'rp': 'IDR',
    'thb': 'THB', 'baht': 'THB',
    'inr': 'INR', 'rupee': 'INR', 'rupees': 'INR',
  };

  // ── Category keywords ─────────────────────────────────────────
  static const _categoryKeywords = <String, String>{
    // Food
    'lunch': 'Food', 'dinner': 'Food', 'breakfast': 'Food',
    'brunch': 'Food', 'meal': 'Food', 'food': 'Food',
    'eat': 'Food', 'ate': 'Food', 'restaurant': 'Food',
    'cafe': 'Food', 'coffee': 'Food', 'tea': 'Food', 'snack': 'Food',
    'grocery': 'Food', 'groceries': 'Food', 'supermarket': 'Food',
    'mcdonalds': 'Food', 'kfc': 'Food', 'pizza': 'Food',
    'burger': 'Food', 'sushi': 'Food', 'ramen': 'Food',
    'delivery': 'Food', 'foodpanda': 'Food', 'grab food': 'Food',
    // Transport
    'petrol': 'Transport', 'gas': 'Transport', 'fuel': 'Transport',
    'grab': 'Transport', 'taxi': 'Transport', 'bus': 'Transport',
    'train': 'Transport', 'mrt': 'Transport', 'lrt': 'Transport',
    'parking': 'Transport', 'toll': 'Transport', 'transport': 'Transport',
    'fare': 'Transport', 'ride': 'Transport', 'car': 'Transport',
    'grabcar': 'Transport', 'uber': 'Transport',
    // Bills
    'electricity': 'Bills & Utilities', 'water': 'Bills & Utilities',
    'internet': 'Bills & Utilities', 'wifi': 'Bills & Utilities',
    'phone': 'Bills & Utilities', 'bill': 'Bills & Utilities',
    'rent': 'Bills & Utilities', 'utility': 'Bills & Utilities',
    'streaming': 'Bills & Utilities',
    // Shopping
    'shop': 'Shopping', 'shopping': 'Shopping', 'clothes': 'Shopping',
    'shoes': 'Shopping', 'bag': 'Shopping', 'amazon': 'Shopping',
    'shopee': 'Shopping', 'lazada': 'Shopping', 'online': 'Shopping',
    'mall': 'Shopping',
    // Entertainment
    'movie': 'Entertainment', 'film': 'Entertainment',
    'ticket': 'Entertainment', 'game': 'Entertainment',
    'netflix': 'Entertainment', 'spotify': 'Entertainment',
    'concert': 'Entertainment', 'sport': 'Entertainment',
    // Health
    'doctor': 'Health', 'clinic': 'Health', 'hospital': 'Health',
    'medicine': 'Health', 'pharmacy': 'Health', 'dental': 'Health',
    'medical': 'Health', 'health': 'Health', 'insurance': 'Health',
    // Education
    'course': 'Education', 'book': 'Education', 'books': 'Education',
    'tuition': 'Education', 'school': 'Education', 'class': 'Education',
    'training': 'Education',
    // Income
    'salary': 'Salary', 'wage': 'Salary', 'paycheck': 'Salary',
    'bonus': 'Salary', 'income': 'Salary',
    'freelance': 'Freelance', 'project': 'Freelance', 'side': 'Freelance',
    'gift': 'Gift', 'angpao': 'Gift',
  };

  @override
  ParsedTransaction? extract(String original) {
    if (original.trim().isEmpty) return null;

    // STT writes "fifteen ringgit", not "15 ringgit".
    final rawText = _wordsToDigits(original);
    final text = rawText.toLowerCase().trim();

    // Step 1 — Extract amount + currency.
    final amountInfo = _extractAmount(text);
    if (amountInfo == null) return null;

    // Step 2 — Classify intent.
    final intent = _detectIntent(text);

    // Step 3 — Detect date.
    final date = _detectDate(text);

    // Step 4 — Classify category.
    final category = _detectCategory(text);

    // Step 5 — Extract note (merchant / description).
    final note = _extractNote(rawText, amountInfo, category);

    final confidence = _calculateConfidence(text, amountInfo, intent, category);

    return ParsedTransaction(
      type: intent,
      amount: amountInfo.amount,
      currency: amountInfo.currency,
      categoryName: category,
      note: note,
      date: date,
      confidence: confidence,
      rawText: original,
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  Spoken numbers ("twenty five" → "25")
  // ──────────────────────────────────────────────────────────────

  static const _numUnits = <String, int>{
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14,
    'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
    'nineteen': 19,
  };
  static const _numTens = <String, int>{
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
    'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };
  static const _numScales = <String, int>{
    'thousand': 1000, 'million': 1000000,
  };

  String _wordsToDigits(String text) {
    final tokens = text.split(RegExp(r'\s+'));
    final out = <String>[];
    var i = 0;
    while (i < tokens.length) {
      final run = _parseNumberRun(tokens, i);
      if (run == null) {
        out.add(tokens[i]);
        i++;
      } else {
        out.add(run.text);
        i = run.end;
      }
    }
    return out.join(' ');
  }

  _NumberRun? _parseNumberRun(List<String> tokens, int start) {
    String core(int k) =>
        k < tokens.length
            ? tokens[k].toLowerCase().replaceAll(RegExp(r'[.,!?;:]+$'), '')
            : '';
    bool isNumWord(String w) =>
        _numUnits.containsKey(w) || _numTens.containsKey(w);

    var total = 0;
    var current = 0;
    var last = ''; // '', unit, tens, hundred, scale, and
    var end = start;
    var j = start;

    while (j < tokens.length) {
      final w = core(j);
      final unit = _numUnits[w];
      final tens = _numTens[w];

      if (unit != null &&
          (last == '' || last == 'hundred' || last == 'scale' || last == 'and' ||
              (last == 'tens' && unit < 10))) {
        current += unit;
        last = unit < 10 ? 'unit' : 'tens';
        end = ++j;
      } else if (tens != null &&
          (last == '' || last == 'hundred' || last == 'scale' || last == 'and')) {
        current += tens;
        last = 'tens';
        end = ++j;
      } else if (w == 'hundred' && (last == 'unit' || last == 'tens')) {
        current *= 100;
        last = 'hundred';
        end = ++j;
      } else if (_numScales.containsKey(w) &&
          (last == 'unit' || last == 'tens' || last == 'hundred')) {
        total += current * _numScales[w]!;
        current = 0;
        last = 'scale';
        end = ++j;
      } else if (w == 'and' &&
          (last == 'hundred' || last == 'scale') &&
          isNumWord(core(j + 1))) {
        last = 'and';
        j++;
      } else if (w == 'a' &&
          j == start &&
          (core(j + 1) == 'hundred' || _numScales.containsKey(core(j + 1)))) {
        current = 1;
        last = 'unit';
        j++;
      } else {
        break;
      }
    }

    if (end == start) return null;

    var number = '${total + current}';
    if (core(end) == 'point') {
      var k = end + 1;
      final digits = StringBuffer();
      while (_numUnits.containsKey(core(k)) && _numUnits[core(k)]! < 10) {
        digits.write(_numUnits[core(k)]);
        k++;
      }
      if (digits.isNotEmpty) {
        number = '$number.$digits';
        end = k;
      }
    }

    final trailing =
        RegExp(r'[.,!?;:]+$').firstMatch(tokens[end - 1])?.group(0) ?? '';
    return _NumberRun('$number$trailing', end);
  }

  // ──────────────────────────────────────────────────────────────
  //  Amount extraction
  // ──────────────────────────────────────────────────────────────

  /// Returns amount and currency, or null.
  _AmountResult? _extractAmount(String text) {
    // Strategy: look for currency-tagged numbers first.
    // Pattern: (currency) (amount) or (amount) (currency).
    final currencyPattern = RegExp(
      r'(rm|myr|usd|sgd|cny|eur|jpy|idr|thb|inr|ringgit|dollar|dollars|'
      r'yuan|rmb|rupiah|baht|yen|euro|euros|rupee|rupees|rp|\$)\s*'
      r'(\d+(?:[.,]\d+)?)',
      caseSensitive: false,
    );
    final amountFirstPattern = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(rm|myr|usd|sgd|cny|eur|jpy|idr|thb|inr|'
      r'ringgit|dollar|dollars|yuan|rmb|rupiah|baht|yen|euro|euros|rupee|rupees|rp|\$)',
      caseSensitive: false,
    );
    final bareNumber = RegExp(r'(\d+(?:[.,]\d+)?)');

    // Check for currency-labeled patterns first.
    for (final pattern in [currencyPattern, amountFirstPattern]) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        String group1 = match.group(1)!.trim();
        String group2 = match.group(2)!.trim();
        // Determine which is the amount and which is the currency keyword.
        final amountStr = RegExp(r'^\d').hasMatch(group1) ? group1 : group2;
        final kw = (!RegExp(r'^\d').hasMatch(group1) ? group1 : group2).toLowerCase();
        final currency = _currencyMap[kw] ?? 'MYR';
        final amount = double.tryParse(amountStr.replaceAll(',', '')) ?? 0;
        if (amount > 0) return _AmountResult(amount, currency);
      }
    }

    // Fallback: any bare number → assume MYR.
    final match = bareNumber.firstMatch(text);
    if (match != null) {
      final amount = double.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
      if (amount > 0) return _AmountResult(amount, 'MYR');
    }

    return null;
  }

  // ──────────────────────────────────────────────────────────────
  //  Intent detection
  // ──────────────────────────────────────────────────────────────

  TransactionType _detectIntent(String text) {
    // Income keywords are stronger signal since they're rarer.
    for (final v in _incomeVerbs) {
      if (text.contains(v)) return TransactionType.income;
    }
    for (final v in _expenseVerbs) {
      if (text.contains(v)) return TransactionType.expense;
    }
    // Default to expense (more common in daily tracking).
    return TransactionType.expense;
  }

  // ──────────────────────────────────────────────────────────────
  //  Category detection
  // ──────────────────────────────────────────────────────────────

  String? _detectCategory(String text) {
    final matches = <String, int>{};
    for (final entry in _categoryKeywords.entries) {
      if (text.contains(entry.key)) {
        matches[entry.value] = (matches[entry.value] ?? 0) + 1;
      }
    }
    if (matches.isEmpty) return null;
    // Return category with most keyword hits.
    return matches.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ──────────────────────────────────────────────────────────────
  //  Date detection
  // ──────────────────────────────────────────────────────────────

  DateTime? _detectDate(String text) {
    final now = DateTime.now();

    if (RegExp(r'\byesterday\b', caseSensitive: false).hasMatch(text)) {
      return DateTime(now.year, now.month, now.day - 1);
    }
    if (RegExp(r'\b(today|now|just now)\b', caseSensitive: false).hasMatch(text)) {
      return DateTime(now.year, now.month, now.day);
    }
    if (RegExp(r'\blast\s+night\b', caseSensitive: false).hasMatch(text)) {
      return DateTime(now.year, now.month, now.day - 1);
    }
    if (RegExp(r'\b(this\s+)?morning\b', caseSensitive: false).hasMatch(text)) {
      return DateTime(now.year, now.month, now.day);
    }

    // "last Monday", "last Tuesday", etc.
    final dayNames = [
      'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'
    ];
    for (int i = 0; i < 7; i++) {
      if (RegExp(r'\blast\s+' + dayNames[i] + r'\b', caseSensitive: false).hasMatch(text)) {
        final diff = (now.weekday - i - 1) % 7 + 7;
        return DateTime(now.year, now.month, now.day - diff);
      }
    }

    // Date format: "on June 15" or "15 June" or "June 15th"
    final datePattern = RegExp(
      r'(?:on\s+)?(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|'
      r'jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)'
      r'\s+(\d{1,2})(?:st|nd|rd|th)?',
      caseSensitive: false,
    );
    final match = datePattern.firstMatch(text);
    if (match != null) {
      final monthStr = match.group(1)!.toLowerCase();
      final day = int.tryParse(match.group(2)!) ?? 1;
      final month = _monthNumber(monthStr);
      final year = month < now.month ? now.year + 1 : now.year;
      return DateTime(year, month, day);
    }

    return null; // default = today
  }

  int _monthNumber(String m) {
    const months = {
      'jan': 1, 'january': 1,
      'feb': 2, 'february': 2,
      'mar': 3, 'march': 3,
      'apr': 4, 'april': 4,
      'may': 5,
      'jun': 6, 'june': 6,
      'jul': 7, 'july': 7,
      'aug': 8, 'august': 8,
      'sep': 9, 'september': 9,
      'oct': 10, 'october': 10,
      'nov': 11, 'november': 11,
      'dec': 12, 'december': 12,
    };
    return months[m] ?? DateTime.now().month;
  }

  // ──────────────────────────────────────────────────────────────
  //  Note extraction
  // ──────────────────────────────────────────────────────────────

  String? _extractNote(String originalText, _AmountResult amountInfo, String? category) {
    // Remove the amount and known keywords, keep remaining as note.
    String text = originalText;

    // Remove amount number.
    text = text.replaceAll(RegExp(r'\d+(?:[.,]\d+)?'), ' ');

    // Remove currency keywords.
    for (final kw in _currencyMap.keys) {
      text = text.replaceAll(RegExp('\\b$kw\\b', caseSensitive: false), ' ');
    }

    // Remove intent verbs.
    for (final v in [..._expenseVerbs, ..._incomeVerbs]) {
      text = text.replaceAll(RegExp('\\b$v\\b', caseSensitive: false), ' ');
    }

    // Remove common filler words.
    final fillers = [
      'i', 'me', 'my', 'a', 'an', 'the', 'on', 'in', 'at', 'to', 'for',
      'of', 'and', 'or', 'with', 'from', 'by', 'it', 'is', 'was', 'we',
      'some', 'just', 'about', 'spent', 'spend', 'paid', 'pay', 'bought',
      'cost', 'had', 'ate', 'got', 'used',
    ];
    for (final f in fillers) {
      text = text.replaceAll(RegExp('\\b$f\\b', caseSensitive: false), ' ');
    }

    // Remove date words.
    final dateWords = [
      'today', 'yesterday', 'tomorrow', 'now', 'just now', 'last night',
      'morning', 'afternoon', 'evening',
    ];
    for (final d in dateWords) {
      text = text.replaceAll(RegExp('\\b$d\\b', caseSensitive: false), ' ');
    }

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isNotEmpty ? text : null;
  }

  // ──────────────────────────────────────────────────────────────
  //  Confidence
  // ──────────────────────────────────────────────────────────────

  double _calculateConfidence(
    String text,
    _AmountResult amountInfo,
    TransactionType intent,
    String? category,
  ) {
    double score = 0.5;

    // Extracted amount → good.
    score += 0.2;

    // Has intent keyword.
    for (final v in _expenseVerbs) {
      if (text.contains(v)) { score += 0.1; break; }
    }
    for (final v in _incomeVerbs) {
      if (text.contains(v)) { score += 0.15; break; }
    }

    // Has category keyword.
    if (category != null) score += 0.1;

    // Penalize very short texts.
    if (text.split(' ').length < 3) score -= 0.15;

    return score.clamp(0.0, 1.0);
  }
}
