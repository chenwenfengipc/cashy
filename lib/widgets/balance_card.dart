import 'package:flutter/material.dart';
import '../utils/currency_utils.dart';

/// Displays the monthly balance, income, and expense summary with a
/// gradient header and optional budget indicator.
class BalanceCard extends StatelessWidget {
  final double balance;
  final double income;
  final double expense;
  final String baseCurrency;
  final String monthLabel;
  final double monthlyBudget; // 0 means no budget set

  const BalanceCard({
    super.key,
    required this.balance,
    required this.income,
    required this.expense,
    required this.baseCurrency,
    required this.monthLabel,
    this.monthlyBudget = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPositive = balance >= 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isPositive
                ? [cs.primaryContainer.withValues(alpha: 0.4), cs.surface]
                : [cs.errorContainer.withValues(alpha: 0.4), cs.surface],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month label.
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(monthLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
                ],
              ),
              const SizedBox(height: 12),

              // Animated balance.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: balance),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return Text(
                    CurrencyUtils.formatInBase(value, baseCurrency),
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isPositive ? cs.primary : cs.error,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Income / Expense row.
              Row(
                children: [
                  _AmountChip(
                    label: 'Income',
                    amount: income,
                    currency: baseCurrency,
                    color: const Color(0xFF2E7D32),
                    icon: Icons.arrow_downward,
                  ),
                  const SizedBox(width: 12),
                  _AmountChip(
                    label: 'Expense',
                    amount: expense,
                    currency: baseCurrency,
                    color: cs.error,
                    icon: Icons.arrow_upward,
                  ),
                ],
              ),

              // Expense / Income ratio bar.
              if (income > 0) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      '${(expense / income * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (expense / income).clamp(0.0, 1.0),
                          backgroundColor: cs.errorContainer.withValues(alpha: 0.5),
                          color: expense > income
                              ? cs.error
                              : cs.primary,
                          minHeight: 6,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // Budget indicator.
              if (monthlyBudget > 0) ...[
                const SizedBox(height: 10),
                _BudgetIndicator(
                  spent: expense,
                  budget: monthlyBudget,
                  baseCurrency: baseCurrency,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  final String label;
  final double amount;
  final String currency;
  final Color color;
  final IconData icon;

  const _AmountChip({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
                Text(
                  CurrencyUtils.formatInBase(amount, currency),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetIndicator extends StatelessWidget {
  final double spent;
  final double budget;
  final String baseCurrency;

  const _BudgetIndicator({
    required this.spent,
    required this.budget,
    required this.baseCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pct = (spent / budget).clamp(0.0, 1.0);
    final remaining = (budget - spent).clamp(0.0, double.infinity);
    final overBudget = spent > budget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              overBudget ? Icons.warning_amber_rounded : Icons.account_balance_wallet_outlined,
              size: 14,
              color: overBudget ? cs.error : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              overBudget
                  ? '🔥 Over budget!'
                  : '💰 Budget: ${CurrencyUtils.formatInBase(remaining, baseCurrency)} left',
              style: theme.textTheme.labelSmall?.copyWith(
                color: overBudget ? cs.error : cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: cs.surfaceContainerHighest,
            color: overBudget ? cs.error : cs.primary,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${CurrencyUtils.formatInBase(spent, baseCurrency)} / ${CurrencyUtils.formatInBase(budget, baseCurrency)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}
