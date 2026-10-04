import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/currency_utils.dart';

/// A single row in the transaction list — card layout with colored left border.
class TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isExpense = transaction.type == TransactionType.expense;
    final color = isExpense ? cs.error : const Color(0xFF2E7D32);
    final sign = isExpense ? '-' : '+';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Dismissible(
        key: Key(transaction.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.delete_outline, color: cs.error),
        ),
        onDismissed: (_) => onDelete?.call(),
        child: Card(
          elevation: 0.3,
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Row(
              children: [
                // Colored left border.
                Container(
                  width: 4,
                  height: 60,
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
                // Category/note + date.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        transaction.note ??
                            transaction.categoryName ??
                            'Transaction',
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
                    '$sign ${CurrencyUtils.format(transaction.amount, transaction.currency)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
