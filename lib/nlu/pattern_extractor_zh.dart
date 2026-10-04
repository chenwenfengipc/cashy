import '../models/transaction.dart';
import 'nlu_extractor.dart';

/// Helper type for amount extraction results (web‑safe alternative to records).
class _AmountResult {
  final double amount;
  final String currency;
  const _AmountResult(this.amount, this.currency);
}

/// Chinese (Mandarin) pattern-based NLU extractor.
///
/// Handles common phrases like:
///  - "中午在麦当劳花了15块钱"
///  - "昨天发工资5000"
///  - "交电费150元"
///  - "在Jaya Grocer买了30令吉的菜"
///  - "打车12块5"
///
/// Chinese note: numbers may be spoken as digits ("15") or
/// Chinese characters ("十五").  We handle both.
class PatternExtractorZh extends NluExtractor {
  @override
  String get language => 'zh';

  // ── Intent keywords ───────────────────────────────────────────
  static const _expenseVerbs = ['花', '买', '交', '付', '请客', '请', '订', '点'];
  // Note: bare '收' is deliberately excluded — it substring-matches inside
  // expense words like '收费' (to be charged) and would misclassify them.
  static const _incomeVerbs = ['发工资', '工资', '收到', '收入', '赚', '挣'];

  // ── Category keywords ─────────────────────────────────────────
  static const _categoryKeywords = <String, String>{
    // Food
    '吃饭': 'Food', '午餐': 'Food', '晚餐': 'Food', '早餐': 'Food',
    '买菜': 'Food', '菜': 'Food', '餐厅': 'Food', '外卖': 'Food',
    '零食': 'Food', '咖啡': 'Food', '茶': 'Food', '水果': 'Food',
    '麦当劳': 'Food', '肯德基': 'Food', 'kfc': 'Food', '海底捞': 'Food',
    '面': 'Food', '饭': 'Food', '吃': 'Food', '喝': 'Food',
    '超市': 'Food', 'supermarket': 'Food', 'grocery': 'Food',
    // Transport
    '油': 'Transport', '打油': 'Transport', '汽油': 'Transport',
    '打车': 'Transport', '出租车': 'Transport', '巴士': 'Transport',
    '地铁': 'Transport', '停车': 'Transport', '交通': 'Transport',
    '车费': 'Transport', 'grab': 'Transport', 'gra': 'Transport',
    '过路费': 'Transport', 'toll': 'Transport', 'parking': 'Transport',
    // Bills
    '电费': 'Bills & Utilities', '水费': 'Bills & Utilities',
    '网费': 'Bills & Utilities', '电话费': 'Bills & Utilities',
    '房租': 'Bills & Utilities', '账单': 'Bills & Utilities',
    '物业': 'Bills & Utilities', '水电': 'Bills & Utilities',
    '宽带': 'Bills & Utilities', 'wifi': 'Bills & Utilities',
    // Shopping
    '买': 'Shopping', '衣服': 'Shopping', '鞋子': 'Shopping',
    '包包': 'Shopping', '网购': 'Shopping', '淘宝': 'Shopping',
    'shopee': 'Shopping', 'lazada': 'Shopping',
    // Entertainment
    '电影': 'Entertainment', '门票': 'Entertainment', '游戏': 'Entertainment',
    '娱乐': 'Entertainment', '唱歌': 'Entertainment', '旅游': 'Entertainment',
    '运动': 'Entertainment', '健身': 'Entertainment',
    // Health
    '看医生': 'Health', '医院': 'Health', '药': 'Health', '诊所': 'Health',
    '牙医': 'Health', '体检': 'Health', '保险': 'Health',
    // Education
    '书': 'Education', '学费': 'Education', '课程': 'Education',
    '培训': 'Education', '补习': 'Education', '报名': 'Education',
    // Income
    '工资': 'Salary', '薪水': 'Salary', '奖金': 'Salary', '收入': 'Salary',
    '月薪': 'Salary', '工钱': 'Salary',
    '自由职业': 'Freelance', '兼职': 'Freelance', '外快': 'Freelance',
    '副业': 'Freelance',
    '红包': 'Gift', '礼物': 'Gift', '赠予': 'Gift',
  };

  // ── Chinese number characters → int ────────────────────────────
  static const _zhDigits = {
    '零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  };
  static const _zhUnits = {'十': 10, '百': 100, '千': 1000, '万': 10000};

  // ── Currency keywords ─────────────────────────────────────────
  static const _currencyMap = {
    '块': 'MYR', '令吉': 'MYR', '马币': 'MYR',
    '元': 'CNY', '人民币': 'CNY',
    '美金': 'USD', '美元': 'USD',
    '新币': 'SGD',
    '日元': 'JPY',
    '泰铢': 'THB',
    '印尼盾': 'IDR', '盾': 'IDR',
    '欧元': 'EUR',
  };

  @override
  ParsedTransaction? extract(String rawText) {
    if (rawText.trim().isEmpty) return null;

    final text = rawText.trim();

    // Step 1 — Extract amount + currency.
    final amountInfo = _extractAmount(text);
    if (amountInfo == null) return null;

    // Step 2 — Classify intent.
    final intent = _detectIntent(text);

    // Step 3 — Detect date.
    final date = _detectDate(text);

    // Step 4 — Classify category.
    final category = _detectCategory(text);

    // Step 5 — Extract note (merchant name / description).
    final note = _extractNote(text, amountInfo, category);

    final confidence = _calculateConfidence(text, amountInfo, intent, category);

    return ParsedTransaction(
      type: intent,
      amount: amountInfo.amount,
      currency: amountInfo.currency,
      categoryName: category,
      note: note,
      date: date,
      confidence: confidence,
      rawText: rawText,
    );
  }

  // ──────────────────────────────────────────────────────────────
  //  Amount extraction
  // ──────────────────────────────────────────────────────────────

  _AmountResult? _extractAmount(String text) {
    // Pattern A: digits followed by currency word (most common).
    // e.g. "15块", "5000块钱", "30令吉", "150元"
    final digitCurrency = RegExp(r'(\d+(?:[.,]\d+)?)\s*(块|令吉|马币|元|人民币|'
        r'美金|美元|新币|日元|泰铢|印尼盾|盾|欧元)');
    final match1 = digitCurrency.firstMatch(text);
    if (match1 != null) {
      final amount = double.tryParse(match1.group(1)!.replaceAll(',', '')) ?? 0;
      final currency = _currencyMap[match1.group(2)] ?? 'MYR';
      if (amount > 0) return _AmountResult(amount, currency);
    }

    // Pattern B: currency word followed by digits.
    // e.g. "令吉15"
    final currencyDigit = RegExp(r'(令吉|马币|rm|RM|MYR|myr)\s*(\d+(?:[.,]\d+)?)');
    final match2 = currencyDigit.firstMatch(text);
    if (match2 != null) {
      final amount = double.tryParse(match2.group(2)!.replaceAll(',', '')) ?? 0;
      if (amount > 0) return _AmountResult(amount, 'MYR');
    }

    // Pattern C: Chinese number characters.
    // e.g. "十五块", "一百二十块"
    final zhNumPattern = RegExp(
        r'([一二三四五六七八九十百千万零两]+)\s*(块|令吉|马币|元|人民币|'
        r'美金|美元|新币|日元|泰铢|印尼盾|盾|欧元)');
    final match3 = zhNumPattern.firstMatch(text);
    if (match3 != null) {
      final amount = _zhNumberToDouble(match3.group(1)!);
      final currency = _currencyMap[match3.group(2)] ?? 'MYR';
      if (amount > 0) return _AmountResult(amount, currency);
    }

    // Pattern D: bare digits without explicit currency word.
    // Check if number is near expense/income keywords.
    final bareNum = RegExp(r'(\d+(?:[.,]\d+)?)');
    final match4 = bareNum.firstMatch(text);
    if (match4 != null) {
      final amount = double.tryParse(match4.group(1)!.replaceAll(',', '')) ?? 0;
      if (amount > 0) return _AmountResult(amount, 'MYR');
    }

    // Pattern E: Chinese number characters without currency word.
    // e.g. "花了十五" → only "十五" with implicit 块
    final zhNumBare = RegExp(r'花(?:了|费)?\s*([一二三四五六七八九十百千万零两]+)');
    final match5 = zhNumBare.firstMatch(text);
    if (match5 != null) {
      final amount = _zhNumberToDouble(match5.group(1)!);
      if (amount > 0) return _AmountResult(amount, 'MYR');
    }

    return null;
  }

  /// Convert Chinese number string like "十五" → 15, "一百二十" → 120.
  double _zhNumberToDouble(String chars) {
    int result = 0;
    int current = 0;

    for (int i = 0; i < chars.length; i++) {
      final char = chars[i];
      if (_zhDigits.containsKey(char)) {
        current = _zhDigits[char]!;
      } else if (_zhUnits.containsKey(char)) {
        final unit = _zhUnits[char]!;
        if (current == 0) current = 1;
        // Commit this magnitude to the running total immediately, so a
        // following digit (e.g. the "五" in "十五" = 15) starts fresh
        // instead of overwriting the tens/hundreds/thousands already
        // accumulated in `current`.
        result += current * unit;
        current = 0;
      }
    }
    result += current;
    return result.toDouble();
  }

  // ──────────────────────────────────────────────────────────────
  //  Intent detection
  // ──────────────────────────────────────────────────────────────
  // Chinese has a clear grammar: 花/买/交/付 → expense,
  // 工资/收到/收入 → income.

  TransactionType _detectIntent(String text) {
    for (final v in _incomeVerbs) {
      if (text.contains(v)) return TransactionType.income;
    }
    // "买了东西" → expense.  "买菜" → also expense.
    for (final v in _expenseVerbs) {
      if (text.contains(v)) return TransactionType.expense;
    }
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
    return matches.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ──────────────────────────────────────────────────────────────
  //  Date detection
  // ──────────────────────────────────────────────────────────────

  DateTime? _detectDate(String text) {
    final now = DateTime.now();

    if (text.contains('昨天') || text.contains('昨晚')) {
      return DateTime(now.year, now.month, now.day - 1);
    }
    if (text.contains('今天') || text.contains('今日') || text.contains('现在') ||
        text.contains('刚才') || text.contains('中午') ||
        text.contains('早上') || text.contains('下午') || text.contains('晚上')) {
      return DateTime(now.year, now.month, now.day);
    }
    if (text.contains('前天')) {
      return DateTime(now.year, now.month, now.day - 2);
    }
    if (text.contains('明天') || text.contains('明日')) {
      return DateTime(now.year, now.month, now.day + 1);
    }

    // "上周一", "上周二" … "上周日"
    final weekdays = ['日', '一', '二', '三', '四', '五', '六'];
    for (int i = 0; i < 7; i++) {
      if (text.contains('上周${weekdays[i]}')) {
        final diff = (now.weekday - i - 1) % 7 + 7;
        return DateTime(now.year, now.month, now.day - diff);
      }
    }

    // "六月十五号" or "6月15号"
    final datePattern = RegExp(r'(\d{1,2}|[一二三四五六七八九十十一十二]+)月'
        r'(\d{1,2}|[一二三四五六七八九十廿卅]+)日?号?');
    final match = datePattern.firstMatch(text);
    if (match != null) {
      final monthStr = match.group(1)!;
      final dayStr = match.group(2)!;

      int month;
      try {
        month = int.parse(monthStr);
      } catch (_) {
        month = _zhSmallNumber(monthStr);
      }
      int day;
      try {
        day = int.parse(dayStr);
      } catch (_) {
        day = _zhSmallNumber(dayStr);
      }

      final year = month < now.month ? now.year + 1 : now.year;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  int _zhSmallNumber(String s) {
    const map = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
      '十一': 11, '十二': 12,
      '廿': 20, '卅': 30,
    };
    return map[s] ?? 0;
  }

  // ──────────────────────────────────────────────────────────────
  //  Note extraction (merchant / description)
  // ──────────────────────────────────────────────────────────────

  String? _extractNote(String text, _AmountResult amountInfo, String? category) {
    // Remove the numbers.
    String cleaned = text.replaceAll(RegExp(r'\d+(?:[.,]\d+)?'), ' ');

    // Remove Chinese number characters.
    cleaned = cleaned.replaceAll(
      RegExp(r'[一二三四五六七八九十百千万零两]+'), ' ');

    // Remove currency words.
    for (final kw in _currencyMap.keys) {
      cleaned = cleaned.replaceAll(kw, ' ');
    }

    // Remove intent verbs.
    for (final v in [..._expenseVerbs, ..._incomeVerbs]) {
      cleaned = cleaned.replaceAll(v, ' ');
    }

    // Keep alphabetic characters (merchant names like "McDonalds", "Jaya Grocer").
    // Keep meaningful Chinese characters that aren't function words.

    // Remove common Chinese function words / particles.
    final fillers = [
      '了', '的', '在', '吧', '吗', '呢', '啊', '哦', '嗯',
      '和', '与', '跟', '同', '及', '以及',
      '就', '都', '也', '还', '又', '再', '才',
      '很', '太', '非常', '比较', '有点',
      '这', '那', '哪', '什么', '怎么', '为什么',
      '个', '只', '种', '样',
      '是', '有', '没有', '不', '没',
      '今天', '昨天', '前天', '明天', '早上', '中午', '下午', '晚上', '昨晚',
      '块钱', '块钱',
    ];
    for (final f in fillers) {
      cleaned = cleaned.replaceAll(f, ' ');
    }

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isNotEmpty ? cleaned : null;
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

    // Extracted amount.
    score += 0.2;

    // Has intent verb.
    for (final v in _expenseVerbs) {
      if (text.contains(v)) { score += 0.1; break; }
    }
    for (final v in _incomeVerbs) {
      if (text.contains(v)) { score += 0.15; break; }
    }

    // Has category.
    if (category != null) score += 0.1;

    // Penalize very short texts (< 3 characters).
    if (text.length < 3) score -= 0.15;

    // Penalize if it's just a bare number.
    if (RegExp(r'^\d+(?:[.,]\d+)?\s*$').hasMatch(text.trim())) score -= 0.2;

    return score.clamp(0.0, 1.0);
  }
}
