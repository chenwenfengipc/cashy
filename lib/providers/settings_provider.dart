import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/settings.dart';
import '../services/rates_service.dart';

/// Manages user settings and exchange rates.
class SettingsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  AppSettings _settings = const AppSettings();
  List<ExchangeRate> _rates = [];
  bool _loaded = false;

  AppSettings get settings => _settings;
  List<ExchangeRate> get rates => _rates;
  bool get isLoaded => _loaded;

  String get baseCurrency => _settings.baseCurrency;
  String get defaultLanguage => _settings.defaultLanguage;

  /// Load settings from DB (should be called once on app start).
  Future<void> load() async {
    _settings = await _db.getSettings();
    _rates = await _db.getExchangeRates();
    _loaded = true;
    notifyListeners();
  }

  /// Update the entire settings object.
  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    await _db.saveSettings(newSettings);
    notifyListeners();
  }

  /// Quick update for base currency only.
  Future<void> setBaseCurrency(String currencyCode) async {
    _settings = _settings.copyWith(baseCurrency: currencyCode);
    await _db.saveSettings(_settings);
    notifyListeners();
  }

  /// Quick update for default language only.
  Future<void> setDefaultLanguage(String lang) async {
    _settings = _settings.copyWith(defaultLanguage: lang);
    await _db.saveSettings(_settings);
    notifyListeners();
  }

  /// Get the exchange rate from [fromCurrency] to base currency.
  Future<double> rateToBase(String fromCurrency) async {
    return _db.convertCurrency(1, fromCurrency, _settings.baseCurrency);
  }

  /// Convert an amount from [fromCurrency] to the user's base currency.
  Future<double> convertToBase(double amount, String fromCurrency) async {
    return _db.convertCurrency(amount, fromCurrency, _settings.baseCurrency);
  }

  /// Save or update an exchange rate.
  Future<void> saveRate(ExchangeRate rate) async {
    await _db.saveExchangeRate(rate);
    _rates = await _db.getExchangeRates();
    notifyListeners();
  }

  /// Drop a hand-typed rate so the automatic one applies again.
  Future<void> clearManualRate(String from, String to) async {
    await _db.deleteExchangeRate(from, to);
    _rates = await _db.getExchangeRates();
    notifyListeners();
  }

  // ── Downloaded rates ────────────────────────────────────────

  final RatesService _ratesService = RatesService();
  bool _refreshing = false;

  bool get ratesDownloadConfigured => _ratesService.isConfigured;
  bool get isRefreshingRates => _refreshing;

  Future<void> setAutoUpdateRates(bool enabled) =>
      updateSettings(_settings.copyWith(autoUpdateRates: enabled));

  /// Download the latest rates now. Returns an error message to show the
  /// user, or null on success. Never throws.
  Future<String?> refreshRates() async {
    if (_refreshing) return null;
    if (!_ratesService.isConfigured) return 'Rate updates are not set up yet.';
    _refreshing = true;
    notifyListeners();
    try {
      await _db.replaceAutoRates(await _ratesService.fetch());
      _settings = _settings.copyWith(ratesUpdatedAt: DateTime.now());
      await _db.saveSettings(_settings);
      _rates = await _db.getExchangeRates();
      return null;
    } on RatesException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not update rates: $e';
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// Called at startup: download rates if auto-update is on and none have
  /// been downloaded yet this calendar month.
  Future<void> autoRefreshRatesIfDue() async {
    if (!_settings.autoUpdateRates || !_ratesService.isConfigured) return;
    final last = _settings.ratesUpdatedAt;
    final now = DateTime.now();
    if (last != null && last.year == now.year && last.month == now.month) {
      return;
    }
    await refreshRates();
  }
}
