import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/settings.dart';
import '../utils/currency_utils.dart';

/// Thrown with a message that is safe to show to the user.
class RatesException implements Exception {
  final String message;
  const RatesException(this.message);

  @override
  String toString() => message;
}

typedef RatesFetcher = Future<String> Function(Uri url);

/// Downloads exchange rates from a small JSON file on the project website.
///
/// Expected file (extra keys are ignored; `tools/update_rates.ps1` writes it):
/// ```json
/// {"base": "USD", "date": "2026-10-02",
///  "rates": {"MYR": 4.0845, "SGD": 1.2798, "CNY": 6.7046}}
/// ```
/// `rates` is how many of each currency one unit of `base` buys. They are
/// stored as `base → X` rows; any other pair is derived from them.
class RatesService {
  /// Public https URL of the rates JSON, e.g.
  /// `https://yourdomain.com/cashy/rates.json`. Empty = rate downloads are
  /// switched off and the related settings are hidden.
  static const ratesUrl = '';

  static const _timeout = Duration(seconds: 10);
  static const _maxBodyBytes = 64 * 1024;

  final RatesFetcher _fetch;
  final String _url;

  RatesService({RatesFetcher? fetcher, String url = ratesUrl})
      : _fetch = fetcher ?? _httpGet,
        _url = url;

  bool get isConfigured => _url.isNotEmpty;

  /// Download and validate the latest rates.
  Future<List<ExchangeRate>> fetch() async {
    final uri = Uri.tryParse(_url);
    if (uri == null || uri.scheme != 'https') {
      throw const RatesException('Rate source is not a valid https address.');
    }
    try {
      return parse(await _fetch(uri));
    } on RatesException {
      rethrow;
    } on TimeoutException {
      throw const RatesException('The rates server took too long to respond.');
    } on SocketException {
      throw const RatesException(
          'Could not reach the rates server. Check your connection.');
    } on HttpException catch (e) {
      throw RatesException('The rates server returned an error (${e.message}).');
    } on TlsException {
      throw const RatesException('Could not make a secure connection.');
    } on FormatException {
      throw const RatesException('The rates file could not be read.');
    }
  }

  /// Turn the downloaded JSON into `base → X` rows for the currencies the
  /// app supports. Throws [RatesException] if nothing usable is found.
  static List<ExchangeRate> parse(String body) {
    final dynamic data;
    try {
      // Editors on Windows sometimes prepend a byte-order mark.
      data = jsonDecode(body.replaceFirst('﻿', ''));
    } on FormatException {
      throw const RatesException('The rates file is not valid JSON.');
    }
    if (data is! Map || data['rates'] is! Map) {
      throw const RatesException('The rates file is in an unexpected format.');
    }
    final base = (data['base'] as String? ?? '').toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(base)) {
      throw const RatesException('The rates file has no valid base currency.');
    }

    final rows = <ExchangeRate>[];
    final raw = data['rates'] as Map;
    for (final code in CurrencyUtils.commonCurrencies) {
      if (code == base) continue;
      final value = raw[code];
      if (value is num && value.isFinite && value > 0) {
        rows.add(ExchangeRate(
            fromCurrency: base, toCurrency: code, rate: value.toDouble()));
      }
    }
    if (rows.length < 2) {
      throw const RatesException('The rates file has too few usable rates.');
    }
    return rows;
  }

  static Future<String> _httpGet(Uri url) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(url).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(_timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBodyBytes) {
          throw const RatesException('The rates file is unexpectedly large.');
        }
      }
      return utf8.decode(bytes);
    } finally {
      client.close(force: true);
    }
  }
}
