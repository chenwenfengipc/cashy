import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/transaction_provider.dart';
import '../widgets/transaction_tile.dart';
import 'voice_input_sheet.dart';

/// Full list of transactions for the selected month — grouped by date.
class TransactionListScreen extends StatelessWidget {
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tx = context.watch<TransactionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(tx.filter.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => tx.previousMonth(),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => tx.nextMonth(),
          ),
        ],
      ),
      body: tx.transactions.isEmpty
          ? _buildEmptyState(context)
          : _buildGroupedList(context, tx),
    );
  }

  // ── Empty state ──

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mic_rounded, size: 48, color: cs.primary),
            ),
            const SizedBox(height: 24),
            Text('No transactions yet',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tap the microphone and speak to add your first entry',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.mic),
              label: const Text('Add Transaction'),
              onPressed: () => _openVoiceInput(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── Grouped list ──

  Widget _buildGroupedList(BuildContext context, TransactionProvider tx) {
    final groups = _groupTransactions(tx.transactions);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        if (group.isHeader) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              group.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          );
        }
        return TransactionTile(
          transaction: group.transaction!,
          onTap: () => _editTransaction(context, group.transaction!),
          onDelete: () => _confirmDelete(context, group.transaction!.id),
        );
      },
    );
  }

  // ── Grouping logic ──

  List<_GroupItem> _groupTransactions(List<Transaction> txs) {
    if (txs.isEmpty) return [];

    final sorted = List<Transaction>.from(txs)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <_GroupItem>[];
    String? currentLabel;

    for (final txn in sorted) {
      final date = DateTime(
        txn.createdAt.year, txn.createdAt.month, txn.createdAt.day,
      );
      final diff = today.difference(date).inDays;
      String label;
      if (diff == 0) {
        label = 'Today';
      } else if (diff == 1) {
        label = 'Yesterday';
      } else if (diff < 7) {
        label = 'This Week';
      } else {
        label = '${_months[txn.createdAt.month - 1]} ${txn.createdAt.year}';
      }

      if (label != currentLabel) {
        groups.add(_GroupItem(label: label, isHeader: true));
        currentLabel = label;
      }
      groups.add(_GroupItem(label: currentLabel!, transaction: txn, isHeader: false));
    }

    return groups;
  }

  // ── Edit dialog ──

  void _editTransaction(BuildContext context, Transaction txn) {
    final typeCtrl = ValueNotifier(txn.type);
    final amountCtrl =
        TextEditingController(text: txn.amount.toStringAsFixed(2));
    final noteCtrl = TextEditingController(text: txn.note ?? '');
    DateTime selectedDate = txn.createdAt;

    showDialog(
      context: context,
      builder: (ctx) {
        return ValueListenableBuilder<TransactionType>(
          valueListenable: typeCtrl,
          builder: (context, type, _) {
            return AlertDialog(
              title: const Text('Edit Transaction'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Type toggle.
                    Row(
                      children: [
                        _editTypeChip(
                          label: 'Expense',
                          selected: type == TransactionType.expense,
                          color: Theme.of(context).colorScheme.error,
                          onTap: () => typeCtrl.value = TransactionType.expense,
                        ),
                        const SizedBox(width: 8),
                        _editTypeChip(
                          label: 'Income',
                          selected: type == TransactionType.income,
                          color: Colors.green.shade700,
                          onTap: () => typeCtrl.value = TransactionType.income,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              selectedDate = picked;
                              (context as Element).markNeedsBuild();
                            }
                          },
                          child: const Text('Change'),
                        ),
                      ],
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
                  onPressed: () {
                    final updated = txn.copyWith(
                      type: typeCtrl.value,
                      amount: double.tryParse(amountCtrl.text) ?? txn.amount,
                      note: noteCtrl.text.isNotEmpty ? noteCtrl.text : null,
                      createdAt: selectedDate,
                    );
                    context
                        .read<TransactionProvider>()
                        .updateTransaction(updated);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _editTypeChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Colors.grey.shade600,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ── Delete confirmation ──

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<TransactionProvider>().deleteTransaction(id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
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

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
}

/// Internal model for grouped list items.
class _GroupItem {
  final String label;
  final bool isHeader;
  final Transaction? transaction;

  _GroupItem({required this.label, required this.isHeader, this.transaction});
}
