import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../utils/currency_utils.dart';

/// Pie chart showing expense category breakdown for the current month.
class CategoryChart extends StatelessWidget {
  final Map<String, double> categoryAmounts;
  final String baseCurrency;

  const CategoryChart({
    super.key,
    required this.categoryAmounts,
    required this.baseCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = categoryAmounts.values.fold<double>(0, (a, b) => a + b);

    if (categoryAmounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('No expenses this month',
            style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant)),
      );
    }

    final sorted = categoryAmounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final colors = _derivedColors(cs);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_outline,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Spending Breakdown',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),

            // Pie chart + legend side by side.
            Row(
              children: [
                // Pie chart.
                SizedBox(
                  width: 140,
                  height: 140,
                  child: _CategoryPieChart(
                    sections: _buildSections(sorted, colors),
                  ),
                ),
                const SizedBox(width: 16),

                // Legend.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PieLegend(
                        entries: sorted,
                        total: total,
                        colors: colors,
                        currency: baseCurrency,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Total row.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Total: ${CurrencyUtils.formatInBase(total, baseCurrency)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Theme-derived color palette.
  List<Color> _derivedColors(ColorScheme cs) {
    return [
      cs.primary,
      cs.tertiary,
      cs.error,
      cs.primary.withValues(alpha: 0.65),
      cs.tertiary.withValues(alpha: 0.65),
      cs.secondary,
      cs.primary.withValues(alpha: 0.4),
      Colors.grey.shade400,
    ];
  }

  List<PieChartSectionData> _buildSections(
      List<MapEntry<String, double>> sorted,
      List<Color> colors) {
    final total =
        sorted.fold<double>(0, (s, e) => s + e.value);
    return sorted.asMap().entries.map((entry) {
      final idx = entry.key;
      final value = entry.value.value;
      final pct = total > 0 ? (value / total) : 0.0;
      return PieChartSectionData(
        value: value,
        color: colors[idx % colors.length],
        radius: pct > 0.15 ? 40 : (pct > 0.05 ? 34 : 28),
        title: '${(pct * 100).toStringAsFixed(0)}%',
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        titlePositionPercentageOffset: 0.6,
      );
    }).toList();
  }
}

/// Separates the touch-interactive pie chart into its own StatefulWidget
/// so touch state (touchedIndex) is maintained.
class _CategoryPieChart extends StatefulWidget {
  final List<PieChartSectionData> sections;

  const _CategoryPieChart({required this.sections});

  @override
  State<_CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<_CategoryPieChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    return PieChart(
      PieChartData(
        sections: _buildSections(),
        centerSpaceRadius: 28,
        sectionsSpace: 2,
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions ||
                response == null ||
                response.touchedSection == null) {
              setState(() => _touchedIndex = -1);
              return;
            }
            setState(() => _touchedIndex =
                response.touchedSection!.touchedSectionIndex);
          },
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildSections() {
    return widget.sections.asMap().entries.map((entry) {
      final idx = entry.key;
      final section = entry.value;
      final isTouched = idx == _touchedIndex;
      return PieChartSectionData(
        value: section.value,
        color: section.color,
        radius: isTouched ? section.radius + 8 : section.radius,
        title: section.title,
        titleStyle: section.titleStyle,
        titlePositionPercentageOffset: section.titlePositionPercentageOffset,
      );
    }).toList();
  }
}

class _PieLegend extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final double total;
  final List<Color> colors;
  final String currency;

  const _PieLegend({
    required this.entries,
    required this.total,
    required this.colors,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = entries.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < display.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _legendRow(display[i], i, theme),
        ],
        if (entries.length > 4)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '+ ${entries.length - 4} more',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _legendRow(
      MapEntry<String, double> entry, int index, ThemeData theme) {
    final pct = total > 0 ? (entry.value / total) : 0.0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colors[index % colors.length],
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            entry.key,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '${(pct * 100).toStringAsFixed(0)}%',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
