/// Persistent app settings stored in SQLite.
class AppSettings {
  final String baseCurrency; // "MYR", "USD", "CNY", etc.
  final String defaultLanguage; // "en" or "zh"
  final double monthlyBudgetLimit; // optional budget cap
  final bool autoUpdateRates; // download rates once a month
  final DateTime? ratesUpdatedAt; // last successful rate download

  const AppSettings({
    this.baseCurrency = 'SGD',
    this.defaultLanguage = 'en',
    this.monthlyBudgetLimit = 0,
    this.autoUpdateRates = true,
    this.ratesUpdatedAt,
  });

  Map<String, dynamic> toMap() => {
        'key': 'app_settings',
        'base_currency': baseCurrency,
        'default_language': defaultLanguage,
        'monthly_budget_limit': monthlyBudgetLimit,
        'auto_update_rates': autoUpdateRates,
        'rates_updated_at': ratesUpdatedAt?.toIso8601String(),
      };

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        baseCurrency: m['base_currency'] as String? ?? 'SGD',
        defaultLanguage: m['default_language'] as String? ?? 'en',
        monthlyBudgetLimit: (m['monthly_budget_limit'] as num?)?.toDouble() ?? 0,
        autoUpdateRates: m['auto_update_rates'] as bool? ?? true,
        ratesUpdatedAt:
            DateTime.tryParse(m['rates_updated_at'] as String? ?? ''),
      );

  AppSettings copyWith({
    String? baseCurrency,
    String? defaultLanguage,
    double? monthlyBudgetLimit,
    bool? autoUpdateRates,
    DateTime? ratesUpdatedAt,
  }) =>
      AppSettings(
        baseCurrency: baseCurrency ?? this.baseCurrency,
        defaultLanguage: defaultLanguage ?? this.defaultLanguage,
        monthlyBudgetLimit: monthlyBudgetLimit ?? this.monthlyBudgetLimit,
        autoUpdateRates: autoUpdateRates ?? this.autoUpdateRates,
        ratesUpdatedAt: ratesUpdatedAt ?? this.ratesUpdatedAt,
      );
}

/// Exchange rate relative to 1 unit of source → target.
/// e.g. source="MYR", target="USD", rate=0.21 means 1 MYR = 0.21 USD.
///
/// [isManual] rates were typed in by the user and survive a monthly
/// download; the rest are built-in estimates or downloaded rates and are
/// replaced on every download.
class ExchangeRate {
  final String fromCurrency;
  final String toCurrency;
  final double rate;
  final bool isManual;

  const ExchangeRate({
    required this.fromCurrency,
    required this.toCurrency,
    required this.rate,
    this.isManual = false,
  });

  Map<String, dynamic> toMap() => {
        'from_currency': fromCurrency,
        'to_currency': toCurrency,
        'rate': rate,
        'is_manual': isManual ? 1 : 0,
      };

  factory ExchangeRate.fromMap(Map<String, dynamic> m) => ExchangeRate(
        fromCurrency: m['from_currency'] as String,
        toCurrency: m['to_currency'] as String,
        rate: (m['rate'] as num).toDouble(),
        isManual: m['is_manual'] == 1 || m['is_manual'] == true,
      );
}
