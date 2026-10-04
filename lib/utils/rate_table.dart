import '../models/settings.dart';

/// Looks up conversion rates between any two currencies from a set of
/// pairwise [ExchangeRate] rows.
///
/// Order tried: a direct row, the inverse of a row, then a two-step path
/// through any third currency (e.g. THB → MYR → SGD). Returns null only if
/// the two currencies are not connected at all.
class RateTable {
  final Map<String, double> _direct = {};
  final Set<String> _currencies = {};

  RateTable(Iterable<ExchangeRate> rates) {
    for (final r in rates) {
      if (!r.rate.isFinite || r.rate <= 0) continue;
      _direct['${r.fromCurrency}>${r.toCurrency}'] = r.rate;
      _currencies
        ..add(r.fromCurrency)
        ..add(r.toCurrency);
    }
  }

  double? _pair(String from, String to) {
    if (from == to) return 1;
    final direct = _direct['$from>$to'];
    if (direct != null) return direct;
    final inverse = _direct['$to>$from'];
    return inverse != null ? 1 / inverse : null;
  }

  /// How many [to] one unit of [from] is worth, or null if unknown.
  double? rate(String from, String to) {
    final pair = _pair(from, to);
    if (pair != null) return pair;
    for (final mid in _currencies) {
      final first = _pair(from, mid);
      if (first == null) continue;
      final second = _pair(mid, to);
      if (second != null) return first * second;
    }
    return null;
  }
}
