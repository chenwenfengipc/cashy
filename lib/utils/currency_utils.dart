/// Currency display and formatting utilities.
class CurrencyUtils {
  /// Currency → symbol map.
  static const symbols = {
    'MYR': 'RM',
    'USD': r'$',
    'CNY': '¥',
    'SGD': 'S\$',
    'IDR': 'Rp',
    'JPY': '¥',
    'THB': '฿',
    'EUR': '€',
    'INR': '₹',
  };

  /// Get the symbol for a currency code.
  static String symbolOf(String code) => symbols[code] ?? code;

  /// Format an amount with currency symbol.
  /// [amount] is in the given [currency], not the base currency.
  static String format(double amount, String currency) {
    final sym = symbolOf(currency);
    final isDecimal = amount != amount.roundToDouble();
    if (isDecimal) {
      return '$sym ${amount.toStringAsFixed(2)}';
    }
    return '$sym ${amount.toStringAsFixed(0)}';
  }

  /// Format in base currency — used for dashboard totals.
  static String formatInBase(double amount, String baseCurrency) {
    return format(amount, baseCurrency);
  }

  /// Compact format for chart axis labels (e.g. "1.2k", "500").
  static String compactFormat(double amount, String currency) {
    final sym = symbolOf(currency);
    if (amount >= 1000000) {
      return '$sym ${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '$sym ${(amount / 1000).toStringAsFixed(1)}k';
    }
    return '$sym ${amount.toStringAsFixed(0)}';
  }

  /// Common currencies list for settings.
  static const commonCurrencies = [
    'MYR', 'USD', 'CNY', 'SGD', 'IDR', 'JPY', 'THB', 'EUR', 'INR',
  ];

  /// User-friendly names.
  static String displayName(String code) {
    const names = {
      'MYR': 'Malaysian Ringgit',
      'USD': 'US Dollar',
      'CNY': 'Chinese Yuan',
      'SGD': 'Singapore Dollar',
      'IDR': 'Indonesian Rupiah',
      'JPY': 'Japanese Yen',
      'THB': 'Thai Baht',
      'EUR': 'Euro',
      'INR': 'Indian Rupee',
    };
    return '${names[code] ?? code} (${symbolOf(code)})';
  }
}
