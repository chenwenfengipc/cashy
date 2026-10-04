import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/settings.dart';
import '../models/transaction.dart';

/// Result of a successful [BackupService.importBackup] call.
class ImportSummary {
  final int transactionsAdded;
  final int transactionsUpdated;
  final int categoriesAdded;
  final int categoriesUpdated;
  final bool settingsRestored;

  const ImportSummary({
    required this.transactionsAdded,
    required this.transactionsUpdated,
    required this.categoriesAdded,
    required this.categoriesUpdated,
    required this.settingsRestored,
  });

  int get totalTransactions => transactionsAdded + transactionsUpdated;
}

/// Exports and imports all app data (transactions, categories, settings,
/// exchange rates) as a single JSON backup file.
///
/// Import is a non-destructive merge: transactions are matched by id
/// (existing rows with the same id are overwritten with the backup's
/// version, new ids are added), categories are matched by name + type.
/// Nothing already in the database is ever deleted by an import.
class BackupService {
  static const _backupVersion = 1;
  static const _fileNamePrefix = 'cashy_backup_';

  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<Map<String, dynamic>> _buildBackup() async {
    final settings = await _db.getSettings();
    final rates = await _db.getExchangeRates();
    final categories = await _db.getCategories();
    final transactions = await _db.getAllTransactions();

    return {
      'app': 'cashy',
      'backup_version': _backupVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'settings': settings.toMap()..remove('key'),
      'exchange_rates': rates.map((r) => r.toMap()).toList(),
      'categories': categories.map((c) => c.toMap()..remove('id')).toList(),
      'transactions': transactions.map((t) => t.toMap()).toList(),
    };
  }

  /// Write a backup JSON file to the app documents directory and return it.
  Future<File> writeBackupFile() async {
    final backup = await _buildBackup();
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final file = File(p.join(dir.path, '$_fileNamePrefix$ts.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(backup));
    return file;
  }

  /// Write a backup file and open the OS share sheet for it (save to
  /// Files/Drive, send by email, AirDrop, etc).
  Future<File> exportAndShare() async {
    final file = await writeBackupFile();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Cashy backup',
      text: 'Cashy expense/income backup — ${p.basename(file.path)}',
    );
    return file;
  }

  /// Absolute path of the folder backups are written to / read from —
  /// shown in the UI so desktop users can find it in a file browser, or
  /// drop in a backup copied from another device.
  Future<String> backupFolderPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// List backup files found in the documents directory, newest first.
  Future<List<File>> listLocalBackups() async {
    final dir = await getApplicationDocumentsDirectory();
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith(_fileNamePrefix) &&
            f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Parse and validate a backup file without importing it.
  Future<Map<String, dynamic>> readBackup(File file) async {
    final dynamic data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic> || data['app'] != 'cashy') {
      throw const FormatException('Not a valid Cashy backup file.');
    }
    return data;
  }

  /// Import a parsed backup. Financial data (transactions, categories)
  /// always merges in. Pass [includeSettings] to also restore the base
  /// currency / language / budget / exchange rates from the backup —
  /// left off by default so restoring onto a device doesn't silently
  /// change its current configuration.
  Future<ImportSummary> importBackup(
    Map<String, dynamic> data, {
    bool includeSettings = false,
  }) async {
    if (includeSettings) {
      final settingsMap = data['settings'];
      if (settingsMap is Map) {
        await _db.saveSettings(
            AppSettings.fromMap(Map<String, dynamic>.from(settingsMap)));
      }
      for (final r in (data['exchange_rates'] as List? ?? [])) {
        await _db.saveExchangeRate(
            ExchangeRate.fromMap(Map<String, dynamic>.from(r as Map)));
      }
    }

    int catAdded = 0, catUpdated = 0;
    final existingCats = await _db.getCategories();
    for (final raw in (data['categories'] as List? ?? [])) {
      final map = Map<String, dynamic>.from(raw as Map)..remove('id');
      final incoming = TransactionCategory.fromMap(map);
      final match = existingCats
          .where((e) => e.name == incoming.name && e.type == incoming.type);
      if (match.isEmpty) {
        await _db.insertCategory(incoming);
        catAdded++;
      } else {
        await _db.updateCategory(incoming.copyWith(id: match.first.id));
        catUpdated++;
      }
    }

    int txAdded = 0, txUpdated = 0;
    final existingIds =
        (await _db.getAllTransactions()).map((t) => t.id).toSet();
    for (final raw in (data['transactions'] as List? ?? [])) {
      final tx = Transaction.fromMap(Map<String, dynamic>.from(raw as Map));
      await _db.insertTransaction(tx);
      if (existingIds.contains(tx.id)) {
        txUpdated++;
      } else {
        txAdded++;
      }
    }

    return ImportSummary(
      transactionsAdded: txAdded,
      transactionsUpdated: txUpdated,
      categoriesAdded: catAdded,
      categoriesUpdated: catUpdated,
      settingsRestored: includeSettings,
    );
  }
}
