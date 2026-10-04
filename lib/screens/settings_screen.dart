import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../providers/settings_provider.dart';
import '../providers/transaction_provider.dart';
import '../models/settings.dart';
import '../utils/currency_utils.dart';
import '../utils/rate_table.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart';
import '../services/backup_service.dart';

/// Settings screen: base currency, language, categories, exchange rates.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backup = BackupService();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── General Section ──
          _SectionCard(
            title: 'General',
            icon: Icons.tune,
            children: [
              _SettingsTile(
                leadingIcon: Icons.currency_exchange,
                title: 'Base Currency',
                subtitle: CurrencyUtils.displayName(settings.baseCurrency),
                onTap: () => _pickCurrency(context, settings),
              ),
              const Divider(height: 1, indent: 56),
              _SettingsTile(
                leadingIcon: Icons.language,
                title: 'Default Language',
                subtitle: settings.defaultLanguage == 'en' ? 'English' : '中文',
                onTap: () => _pickLanguage(context, settings),
              ),
              const Divider(height: 1, indent: 56),
              _SettingsTile(
                leadingIcon: Icons.account_balance_wallet_outlined,
                title: 'Monthly Budget Limit',
                subtitle: settings.settings.monthlyBudgetLimit > 0
                    ? CurrencyUtils.formatInBase(
                        settings.settings.monthlyBudgetLimit,
                        settings.baseCurrency)
                    : 'Not set',
                onTap: () => _setBudget(context, settings),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Exchange Rates Section ──
          _SectionCard(
            title: 'Exchange Rates',
            icon: Icons.currency_exchange,
            children: [
              if (settings.ratesDownloadConfigured) ...[
                SwitchListTile(
                  secondary: CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.5),
                    child: Icon(Icons.autorenew,
                        size: 18, color: Theme.of(context).colorScheme.primary),
                  ),
                  title: const Text('Update rates monthly',
                      style: TextStyle(fontSize: 15)),
                  subtitle: Text(
                    'Download current rates once a month when online',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  value: settings.settings.autoUpdateRates,
                  onChanged: settings.setAutoUpdateRates,
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  leadingIcon: Icons.sync,
                  title: 'Update now',
                  subtitle: settings.isRefreshingRates
                      ? 'Updating…'
                      : _ratesStatus(settings),
                  onTap: settings.isRefreshingRates
                      ? null
                      : () => _refreshRates(settings),
                ),
                const Divider(height: 1, indent: 56),
              ],
              ..._rateTiles(context, settings),
            ],
          ),

          const SizedBox(height: 16),

          // ── Categories Section ──
          _SectionCard(
            title: 'Categories',
            icon: Icons.category,
            children: [
              FutureBuilder<List<TransactionCategory>>(
                future: DatabaseHelper.instance.getCategories(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  final cats = snapshot.data!;
                  return Column(
                    children: cats.asMap().entries.map((entry) {
                      return Column(
                        children: [
                          if (entry.key > 0)
                            const Divider(height: 1, indent: 56),
                          _SettingsTile(
                            leadingIcon: Icons.label_outline,
                            title: '${entry.value.icon}  ${entry.value.name}',
                            subtitle: entry.value.type == TransactionType.expense
                                ? 'Expense'
                                : 'Income',
                            onTap: () => _editCategory(context, entry.value),
                          ),
                        ],
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Backup & Restore Section ──
          _SectionCard(
            title: 'Backup & Restore',
            icon: Icons.backup_outlined,
            children: [
              _SettingsTile(
                leadingIcon: Icons.ios_share,
                title: 'Export Backup',
                subtitle: 'Save all transactions & categories to a file',
                onTap: _busy ? null : _exportBackup,
              ),
              const Divider(height: 1, indent: 56),
              _SettingsTile(
                leadingIcon: Icons.restore,
                title: 'Restore from Backup',
                subtitle: 'Import transactions & categories from a file',
                onTap: _busy ? null : _restoreBackup,
              ),
            ],
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'Cashy v1.0.0',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Dialogs ─────────────────────────────────────────────────

  void _pickCurrency(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Base Currency'),
        children: CurrencyUtils.commonCurrencies.map((code) {
          return SimpleDialogOption(
            onPressed: () {
              settings.setBaseCurrency(code);
              Navigator.pop(ctx);
            },
            child: Text(CurrencyUtils.displayName(code)),
          );
        }).toList(),
      ),
    );
  }

  void _pickLanguage(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Default Language'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              settings.setDefaultLanguage('en');
              Navigator.pop(ctx);
            },
            child: const Text('English'),
          ),
          SimpleDialogOption(
            onPressed: () {
              settings.setDefaultLanguage('zh');
              Navigator.pop(ctx);
            },
            child: const Text('中文 (Chinese)'),
          ),
        ],
      ),
    );
  }

  void _setBudget(BuildContext context, SettingsProvider settings) {
    final ctrl = TextEditingController(
      text: settings.settings.monthlyBudgetLimit > 0
          ? settings.settings.monthlyBudgetLimit.toString()
          : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Monthly Budget'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: 'Limit in ${settings.baseCurrency}',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final limit = double.tryParse(ctrl.text) ?? 0;
              settings.updateSettings(
                settings.settings.copyWith(monthlyBudgetLimit: limit),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  List<Widget> _rateTiles(BuildContext context, SettingsProvider settings) {
    final table = RateTable(settings.rates);
    final base = settings.baseCurrency;
    final codes =
        CurrencyUtils.commonCurrencies.where((c) => c != base).toList();

    return [
      for (int i = 0; i < codes.length; i++)
        Column(
          children: [
            if (i > 0) const Divider(height: 1, indent: 56),
            Builder(builder: (context) {
              final code = codes[i];
              final rate = table.rate(code, base);
              final manual = settings.rates.any((r) =>
                  r.fromCurrency == code &&
                  r.toCurrency == base &&
                  r.isManual);
              return _SettingsTile(
                leadingIcon: Icons.swap_horiz,
                title: '1 $code',
                subtitle: rate == null
                    ? 'Not available — tap to set'
                    : '= ${_fmtRate(rate)} $base${manual ? '  ·  set by you' : ''}',
                onTap: () => _editRate(context, settings, code, rate, manual),
              );
            }),
          ],
        ),
    ];
  }

  String _ratesStatus(SettingsProvider settings) {
    final last = settings.settings.ratesUpdatedAt;
    if (last == null) return 'Using built-in estimates — tap to download the latest';
    return 'Last updated ${DateFormat.yMMMd().format(last)}';
  }

  Future<void> _refreshRates(SettingsProvider settings) async {
    final error = await settings.refreshRates();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Exchange rates updated.')),
    );
  }

  void _editRate(BuildContext context, SettingsProvider settings, String code,
      double? current, bool manual) {
    final base = settings.baseCurrency;
    final ctrl =
        TextEditingController(text: current != null ? _fmtRate(current) : '');
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('1 $code = ? $base'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Rate',
              errorText: error,
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if (manual)
              TextButton(
                onPressed: () {
                  settings.clearManualRate(code, base);
                  Navigator.pop(ctx);
                },
                child: const Text('Use automatic'),
              ),
            FilledButton(
              onPressed: () {
                final newRate =
                    double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
                if (newRate == null || newRate <= 0 || !newRate.isFinite) {
                  setDialogState(() => error = 'Enter a number above 0');
                  return;
                }
                settings.saveRate(ExchangeRate(
                  fromCurrency: code,
                  toCurrency: base,
                  rate: newRate,
                  isManual: true,
                ));
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _editCategory(BuildContext context, TransactionCategory cat) {
    final nameCtrl = TextEditingController(text: cat.name);
    final enCtrl = TextEditingController(text: cat.keywordsEn.join(', '));
    final zhCtrl = TextEditingController(text: cat.keywordsZh.join(', '));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${cat.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: enCtrl,
                decoration:
                    const InputDecoration(labelText: 'English keywords'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: zhCtrl,
                decoration:
                    const InputDecoration(labelText: 'Chinese keywords'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final updated = cat.copyWith(
                name: nameCtrl.text,
                keywordsEn: enCtrl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList(),
                keywordsZh: zhCtrl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList(),
              );
              await DatabaseHelper.instance.updateCategory(updated);
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Backup / Restore ────────────────────────────────────────

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final file = await _backup.exportAndShare();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup saved: ${p.basename(file.path)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final files = await _backup.listLocalBackups();
    if (!mounted) return;

    final folder = await _backup.backupFolderPath();
    if (!mounted) return;

    if (files.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No Backups Found'),
          content: Text(
            'No backup files were found in:\n$folder\n\n'
            'Export a backup first, or — to restore from another device — '
            'copy its exported .json file into that folder, then try again.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: folder));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder path copied')),
                );
              },
              child: const Text('Copy Path'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final chosen = await showDialog<File>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose a Backup'),
        children: files.map((f) {
          final stat = f.statSync();
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.basename(f.path)),
                Text(
                  stat.modified.toString().split('.').first,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (chosen == null || !mounted) return;

    bool includeSettings = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Restore Backup?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Transactions and categories from "${p.basename(chosen.path)}" '
                  'will be merged into your current data. Nothing already on '
                  'this device will be deleted.'),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Also restore currency, language, budget '
                    'and exchange-rate settings'),
                value: includeSettings,
                onChanged: (v) =>
                    setDialogState(() => includeSettings = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final data = await _backup.readBackup(chosen);
      final summary = await _backup.importBackup(
        data,
        includeSettings: includeSettings,
      );
      if (!mounted) return;

      // Reload providers so the UI reflects the newly-imported data.
      final settingsProvider = context.read<SettingsProvider>();
      final txProvider = context.read<TransactionProvider>();
      await settingsProvider.load();
      await txProvider.load();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restored ${summary.totalTransactions} transaction(s), '
            '${summary.categoriesAdded + summary.categoriesUpdated} categor'
            '${summary.categoriesAdded + summary.categoriesUpdated == 1 ? 'y' : 'ies'}'
            '${summary.settingsRestored ? ', settings' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Up to 4 significant digits, no trailing zeros (0.2900 → 0.29, 17950 → 17950).
String _fmtRate(double rate) {
  var s = rate >= 1000 ? rate.toStringAsFixed(2) : rate.toStringAsPrecision(4);
  if (s.contains('.') && !s.contains('e')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// A card that wraps a settings section with a header.
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// A single tappable row inside a settings section.
class _SettingsTile extends StatelessWidget {
  final IconData leadingIcon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.leadingIcon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: cs.primaryContainer.withValues(alpha: 0.5),
        child: Icon(leadingIcon, size: 18, color: cs.primary),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(subtitle,
          style: TextStyle(
            fontSize: 13,
            color: cs.onSurfaceVariant,
          )),
      trailing: onTap != null
          ? Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant)
          : null,
      onTap: onTap,
    );
  }
}
