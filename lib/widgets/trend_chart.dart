import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../utils/currency_utils.dart';

/// Bar chart showing monthly income vs expense for the last 6 months.
class TrendChart extends StatelessWidget {
  final List<MonthlyTotal> data;
  final String baseCurrency;

  const TrendChart({
    super.key,
    required this.data,
    required this.baseCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (data.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Monthly Trend',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _maxValue * 1.2,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final item = data[groupIndex];
                        return BarTooltipItem(
                          '${item.label}\n',
                          const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12),
                          children: [
                            TextSpan(
                              text: rodIndex == 0
                                  ? 'Inc: ${CurrencyUtils.formatInBase(item.income, baseCurrency)}'
                                  : 'Exp: ${CurrencyUtils.formatInBase(item.expense, baseCurrency)}',
                              style: TextStyle(
                                color: rodIndex == 0
                                    ? const Color(0xFF2E7D32)
                                    : cs.error,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) => Text(
                          CurrencyUtils.compactFormat(value, baseCurrency),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= data.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              data[idx].label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _maxValue > 0 ? _maxValue / 4 : 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: cs.outlineVariant,
                      strokeWidth: 1,
                    ),
                  ),
                  barGroups: _buildBarGroups(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _maxValue {
    double max = 0;
    for (final d in data) {
      if (d.income > max) max = d.income;
      if (d.expense > max) max = d.expense;
    }
    return max;
  }

  List<BarChartGroupData> _buildBarGroups() {
    return data.asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      return BarChartGroupData(
        x: idx,
        barRods: [
          BarChartRodData(
            toY: item.income,
            color: Colors.green.shade400,
            width: 10,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(3),
              topRight: Radius.circular(3),
            ),
          ),
          BarChartRodData(
            toY: item.expense,
            color: Colors.red.shade400,
            width: 10,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(3),
              topRight: Radius.circular(3),
            ),
          ),
        ],
      );
    }).toList();
  }
}
