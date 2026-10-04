import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/transaction_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/currency_utils.dart';
import '../widgets/balance_card.dart';
import '../widgets/category_chart.dart';
import '../widgets/trend_chart.dart';
import 'transaction_list_screen.dart';
import 'voice_input_sheet.dart';

/// Main dashboard showing balance, categories, trend, and quick actions.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final txProvider = context.watch<TransactionProvider>();
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(txProvider.isLoaded ? txProvider.filter.label : 'Cashy'),
        actions: [
          // Language toggle.
          IconButton(
            icon: Text(
              settings.defaultLanguage == 'en' ? 'EN' : '中文',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              final newLang = settings.defaultLanguage == 'en' ? 'zh' : 'en';
              settings.setDefaultLanguage(newLang);
            },
          ),
          // Settings.
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: txProvider.isLoaded
          ? _buildContent(context, txProvider, settings)
          : const Center(child: CircularProgressIndicator()),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'speak',
        onPressed: () => _openVoiceInput(context),
        icon: const Icon(Icons.mic),
        label: const Text('Speak'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TransactionProvider tx,
      SettingsProvider settings) {
    return RefreshIndicator(
      onRefresh: () => tx.load(),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! > 200) {
            tx.previousMonth();
          } else if (details.primaryVelocity! < -200) {
            tx.nextMonth();
          }
        },
        child: ListView(
          children: [
            const SizedBox(height: 4),

            // ── Greeting header ──
            _GreetingHeader(),

            // ── Month navigation ──
            _MonthNav(
              label: tx.filter.label,
              onPrev: () => tx.previousMonth(),
              onNext: () => tx.nextMonth(),
            ),

            // Balance card with budget.
            BalanceCard(
              balance: tx.balance,
              income: tx.totalIncome,
              expense: tx.totalExpense,
              baseCurrency: settings.baseCurrency,
              monthLabel: tx.filter.label,
              monthlyBudget: settings.settings.monthlyBudgetLimit,
            ),

            // Category pie chart.
            CategoryChart(
              categoryAmounts: tx.categoryBreakdown,
              baseCurrency: settings.baseCurrency,
            ),

            // Monthly trend chart.
            if (tx.monthlyTrend.isNotEmpty)
              TrendChart(
                data: tx.monthlyTrend,
                baseCurrency: settings.baseCurrency,
              ),

            const SizedBox(height: 8),

            // Recent transactions header.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.history,
                      size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('Recent',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TransactionListScreen()),
                    ),
                    child: const Text('See All'),
                  ),
                ],
              ),
            ),

            // Recent 5 transactions — card-based tiles.
            if (tx.transactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Text(
                  'No transactions yet. Tap Speak to add one.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
              )
            else
              ...tx.transactions.take(5).map(
                    (txn) => _RecentTile(
                      transaction: txn,
                      baseCurrency: settings.baseCurrency,
                    ),
                  ),

            const SizedBox(height: 80), // FAB padding
          ],
        ),
      ),
    );
  }

  void _openVoiceInput(BuildContext context) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceInputSheet(),
    );

    if (result != null && context.mounted) {
      final parsed = result['parsed'] as dynamic;
      final amountInBase = result['amountInBase'] as double;
      if (parsed != null) {
        context.read<TransactionProvider>().addTransaction(
              parsed,
              amountInBase: amountInBase,
            );
      }
    }
  }
}

/// Time-based greeting header.
class _GreetingHeader extends StatelessWidget {
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = _greeting();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: Padding(
        key: ValueKey(greeting),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$greeting 👋',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Here's your money overview",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded-pill month navigation with swipe support.
class _MonthNav extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthNav({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Text(label,
                  key: ValueKey(label),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
          ),
        ],
      ),
    );
  }
}

/// Card-based tile for the Recent list on the dashboard.
class _RecentTile extends StatelessWidget {
  final dynamic transaction;
  final String baseCurrency;

  const _RecentTile({
    required this.transaction,
    required this.baseCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isExpense = _isExpense(transaction);
    final color = isExpense ? cs.error : const Color(0xFF2E7D32);
    final sign = isExpense ? '-' : '+';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      elevation: 0.3,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {},
        child: Row(
          children: [
            // Colored left border.
            Container(
              width: 4,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Emoji.
            Text(
              _categoryEmoji(transaction.categoryName),
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 12),
            // Note + date.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    transaction.note ?? transaction.categoryName ?? 'Transaction',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(transaction.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Amount.
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '$sign ${CurrencyUtils.formatInBase(transaction.amountInBase, baseCurrency)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isExpense(dynamic txn) {
    try {
      final typeField = txn.type;
      if (typeField is TransactionType) {
        return typeField == TransactionType.expense;
      }
      return typeField == 'expense';
    } catch (_) {
      return true;
    }
  }

  String _categoryEmoji(String? category) {
    const emojis = {
      'Food': '🍔',
      'Transport': '🚗',
      'Bills & Utilities': '⚡',
      'Shopping': '🛍️',
      'Entertainment': '🎬',
      'Health': '🏥',
      'Education': '📚',
      'Salary': '💰',
      'Freelance': '💼',
      'Gift': '🎁',
    };
    return emojis[category] ?? '📦';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${dt.day} ${_months[dt.month - 1]}';
    return '${dt.day} ${_months[dt.month - 1]}';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
}
