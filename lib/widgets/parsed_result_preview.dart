import 'package:flutter/material.dart';
import '../models/transaction.dart';

/// Shows the auto-parsed transaction result with editable fields.
class ParsedResultPreview extends StatefulWidget {
  final ParsedTransaction result;
  final ValueChanged<ParsedTransaction> onChanged;

  const ParsedResultPreview({
    super.key,
    required this.result,
    required this.onChanged,
  });

  @override
  State<ParsedResultPreview> createState() => _ParsedResultPreviewState();
}

class _ParsedResultPreviewState extends State<ParsedResultPreview> {
  late TransactionType _type;
  late TextEditingController _amountCtrl;
  late String _currency;
  late String _category;
  late TextEditingController _noteCtrl;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _initFrom(widget.result);
  }

  @override
  void didUpdateWidget(ParsedResultPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.result != oldWidget.result) {
      _initFrom(widget.result);
    }
  }

  void _initFrom(ParsedTransaction r) {
    _type = r.type;
    _amountCtrl = TextEditingController(text: r.amount.toStringAsFixed(2));
    _currency = r.currency;
    _category = r.categoryName ?? '';
    _noteCtrl = TextEditingController(text: r.note ?? '');
    _date = r.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    widget.onChanged(ParsedTransaction(
      type: _type,
      amount: amount,
      currency: _currency,
      categoryName: _category.isNotEmpty ? _category : null,
      note: _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
      date: _date,
      confidence: widget.result.confidence,
      rawText: widget.result.rawText,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = _type == TransactionType.expense;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Confidence indicator.
        if (widget.result.confidence < 0.7)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Low confidence — please review',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade900)),
                ),
              ],
            ),
          ),

        // Type toggle.
        Row(
          children: [
            _TypeChip(
              label: 'Expense',
              icon: Icons.trending_down,
              selected: isExpense,
              color: Colors.red,
              onTap: () => setState(() { _type = TransactionType.expense; _emit(); }),
            ),
            const SizedBox(width: 8),
            _TypeChip(
              label: 'Income',
              icon: Icons.trending_up,
              selected: !isExpense,
              color: Colors.green,
              onTap: () => setState(() { _type = TransactionType.income; _emit(); }),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Amount + currency row.
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: ['MYR', 'USD', 'CNY', 'SGD', 'IDR', 'JPY', 'EUR', 'THB']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() { _currency = v; _emit(); });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Category.
        DropdownButtonFormField<String>(
          initialValue: _category.isNotEmpty ? _category : null,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: ['Food', 'Transport', 'Bills & Utilities', 'Shopping',
                  'Entertainment', 'Health', 'Education', 'Salary',
                  'Freelance', 'Gift', 'Others']
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() { _category = v; _emit(); });
          },
        ),
        const SizedBox(height: 12),

        // Note.
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Note / Merchant',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 12),

        // Date.
        Row(
          children: [
            Text('Date: ', style: theme.textTheme.bodyMedium),
            TextButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                '${_date.day}/${_date.month}/${_date.year}',
              ),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 30)),
                );
                if (picked != null) {
                  setState(() { _date = picked; _emit(); });
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? color : Colors.grey),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: selected ? color : Colors.grey.shade700,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
