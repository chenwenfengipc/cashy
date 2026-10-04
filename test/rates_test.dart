import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cashy/models/settings.dart';
import 'package:cashy/services/rates_service.dart';
import 'package:cashy/utils/rate_table.dart';

ExchangeRate _r(String from, String to, double rate) =>
    ExchangeRate(fromCurrency: from, toCurrency: to, rate: rate);

const _goodJson = '''
{"version": 1, "base": "USD", "date": "2026-10-02",
 "rates": {"CNY": 6.7046, "EUR": 0.89087, "IDR": 17950, "INR": 96.32,
           "JPY": 157.67, "MYR": 4.0845, "SGD": 1.2798, "THB": 33.595,
           "XXX": 5}}
''';

void main() {
  group('RateTable', () {
    // The built-in seed rows: everything is linked through MYR.
    final seed = [
      _r('MYR', 'USD', 0.21),
      _r('MYR', 'SGD', 0.29),
      _r('MYR', 'THB', 7.7),
      _r('USD', 'MYR', 4.70),
      _r('SGD', 'MYR', 3.45),
    ];

    test('direct row wins', () {
      expect(RateTable(seed).rate('MYR', 'SGD'), 0.29);
    });

    test('inverse of a row when only the opposite pair exists', () {
      expect(RateTable(seed).rate('THB', 'MYR'), closeTo(1 / 7.7, 1e-12));
    });

    test('derives a pair through a third currency', () {
      // USD → MYR → SGD: this pair has no row of its own.
      expect(RateTable(seed).rate('USD', 'SGD'), closeTo(4.70 * 0.29, 1e-12));
      expect(RateTable(seed).rate('THB', 'SGD'), closeTo(0.29 / 7.7, 1e-12));
    });

    test('same currency is 1; unconnected currencies are null', () {
      expect(RateTable(seed).rate('SGD', 'SGD'), 1);
      expect(RateTable(seed).rate('INR', 'SGD'), isNull);
    });

    test('ignores invalid rows', () {
      final t = RateTable([_r('A', 'B', 0), _r('A', 'C', double.nan)]);
      expect(t.rate('A', 'B'), isNull);
      expect(t.rate('A', 'C'), isNull);
    });

    test('downloaded base→X rows connect every currency', () {
      final t = RateTable(RatesService.parse(_goodJson));
      expect(t.rate('MYR', 'SGD'), closeTo(1.2798 / 4.0845, 1e-9));
      expect(t.rate('IDR', 'THB'), closeTo(33.595 / 17950, 1e-9));
    });
  });

  group('RatesService.parse', () {
    test('keeps supported currencies only', () {
      final rows = RatesService.parse(_goodJson);
      expect(rows.map((r) => r.toCurrency).toSet(),
          {'CNY', 'EUR', 'IDR', 'INR', 'JPY', 'MYR', 'SGD', 'THB'});
      expect(rows.every((r) => r.fromCurrency == 'USD' && !r.isManual), isTrue);
    });

    test('accepts a byte-order mark', () {
      expect(RatesService.parse('﻿$_goodJson'), isNotEmpty);
    });

    test('rejects bad files with a readable message', () {
      for (final bad in [
        'not json',
        '[]',
        '{"base":"USD"}',
        '{"base":"","rates":{"MYR":4}}',
        '{"base":"USD","rates":{"MYR":-1,"SGD":0,"CNY":"x"}}',
        '{"base":"USD","rates":{"MYR":4.1}}',
      ]) {
        expect(() => RatesService.parse(bad), throwsA(isA<RatesException>()),
            reason: bad);
      }
    });
  });

  group('RatesService.fetch', () {
    const url = 'https://example.com/rates.json';

    test('is disabled with no url', () {
      expect(RatesService().isConfigured, isFalse);
    });

    test('downloads and parses', () async {
      final svc = RatesService(url: url, fetcher: (_) async => _goodJson);
      expect(svc.isConfigured, isTrue);
      expect(await svc.fetch(), hasLength(8));
    });

    test('refuses a non-https url', () async {
      final svc = RatesService(
          url: 'http://example.com/rates.json', fetcher: (_) async => _goodJson);
      expect(svc.fetch(), throwsA(isA<RatesException>()));
    });

    test('turns network failures into readable errors', () async {
      for (final error in <Object>[
        const SocketException('offline'),
        TimeoutException('slow'),
        const HttpException('HTTP 404'),
        const FormatException('bad utf8'),
      ]) {
        final svc = RatesService(url: url, fetcher: (_) async => throw error);
        expect(svc.fetch(), throwsA(isA<RatesException>()), reason: '$error');
      }
    });
  });

  test('ExchangeRate keeps its manual flag through a backup round trip', () {
    final back = ExchangeRate.fromMap(
        ExchangeRate(fromCurrency: 'USD', toCurrency: 'SGD', rate: 1.3, isManual: true)
            .toMap());
    expect(back.isManual, isTrue);
    // Backups made before the flag existed have no such key.
    expect(
        ExchangeRate.fromMap(
                {'from_currency': 'USD', 'to_currency': 'SGD', 'rate': 1.3})
            .isManual,
        isFalse);
  });

  test('AppSettings round trip keeps the new fields; old data gets defaults', () {
    final when = DateTime(2026, 10, 2, 8);
    final back = AppSettings.fromMap(
        const AppSettings(autoUpdateRates: false).copyWith(ratesUpdatedAt: when).toMap());
    expect(back.autoUpdateRates, isFalse);
    expect(back.ratesUpdatedAt, when);

    final old = AppSettings.fromMap({'base_currency': 'MYR'});
    expect(old.autoUpdateRates, isTrue);
    expect(old.ratesUpdatedAt, isNull);
  });
}
