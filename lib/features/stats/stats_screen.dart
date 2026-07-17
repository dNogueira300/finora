import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';

/// Color de respaldo para una categoria que ya no existe (borrada) pero que
/// sigue referenciada por transacciones historicas del mes.
const _fallbackCategoryColor = Color(0xFF6B7280);

/// Mes calendario mostrado por la pantalla (chevrons para navegar). Arranca
/// en el mes actual.
final _statsMonthProvider = StateProvider<DateTime>((_) {
  final now = toLima(DateTime.now().toUtc());
  return DateTime(now.year, now.month, 1);
});

/// Gastos del mes seleccionado, agrupados por `categoryId` (en centavos).
final _categoryTotalsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) {
  final month = ref.watch(_statsMonthProvider);
  return ref.watch(databaseProvider).transactionsDao.totalsByCategory(month);
});

/// Categorias de gasto, para resolver nombre/color de cada `categoryId` de
/// `_categoryTotalsProvider` en la leyenda del donut.
final _expenseCategoriesProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(databaseProvider).categoriesDao.watchByKind('expense');
});

/// Un punto de la serie "Evolucion mensual": gasto e ingreso totales de un
/// mes calendario (en centavos).
typedef _MonthPoint = ({DateTime month, int expense, int income});

/// Los ultimos 6 meses (incluyendo el mes seleccionado) de gasto vs ingreso.
final _sixMonthSeriesProvider = FutureProvider.autoDispose<List<_MonthPoint>>((ref) async {
  final dao = ref.watch(databaseProvider).transactionsDao;
  final base = ref.watch(_statsMonthProvider);
  final out = <_MonthPoint>[];
  for (var i = 5; i >= 0; i--) {
    final m = DateTime(base.year, base.month - i, 1);
    out.add((
      month: m,
      expense: await dao.monthlyTotal(kind: 'expense', month: m),
      income: await dao.monthlyTotal(kind: 'income', month: m),
    ));
  }
  return out;
});

/// Capitaliza la primera letra de un label ya formateado (mismo patron que
/// `_MonthHeader` en `calendar_screen.dart`).
String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Pantalla "Análisis" (referencia Stitch "Análisis Financiero Premium"):
/// selector de mes, donut de gastos por categoria con leyenda (monto y
/// porcentaje), y barras "Evolución mensual" con gasto vs ingreso de los
/// ultimos 6 meses.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(_statsMonthProvider);
    final categoryTotalsAsync = ref.watch(_categoryTotalsProvider);
    final categoriesAsync = ref.watch(_expenseCategoriesProvider);
    final seriesAsync = ref.watch(_sixMonthSeriesProvider);
    final categoriesById = {
      for (final c in categoriesAsync.valueOrNull ?? const <Category>[]) c.id: c,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Análisis')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MonthSelector(
              month: month,
              onPrevious: () => _shiftMonth(ref, -1),
              onNext: () => _shiftMonth(ref, 1),
            ),
            const SizedBox(height: 16),
            Text('Gastos por categoría', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            categoryTotalsAsync.when(
              data: (totals) => _DonutSection(totals: totals, categoriesById: categoriesById),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Center(child: Text('No se pudo cargar: $e')),
            ),
            const SizedBox(height: 24),
            Text('Evolución mensual', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            seriesAsync.when(
              data: (series) => _MonthlyBarChart(series: series),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Center(child: Text('No se pudo cargar: $e')),
            ),
            const SizedBox(height: 8),
            const _BarLegend(),
          ],
        ),
      ),
    );
  }
}

void _shiftMonth(WidgetRef ref, int delta) {
  final m = ref.read(_statsMonthProvider);
  ref.read(_statsMonthProvider.notifier).state = DateTime(m.year, m.month + delta, 1);
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.month, required this.onPrevious, required this.onNext});
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final label = _capitalize(DateFormat('MMMM yyyy', 'es').format(month));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mes anterior',
          onPressed: onPrevious,
        ),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Mes siguiente',
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Donut de gastos por categoria (centro con el total del mes) + leyenda con
/// monto y porcentaje por categoria. Si el mes no tiene gastos, muestra un
/// mensaje vacio en vez de un donut sin datos.
class _DonutSection extends StatelessWidget {
  const _DonutSection({required this.totals, required this.categoriesById});
  final Map<String, int> totals;
  final Map<String, Category> categoriesById;

  @override
  Widget build(BuildContext context) {
    final totalCents = totals.values.fold<int>(0, (a, b) => a + b);
    if (totalCents <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'Sin gastos este mes',
            style: TextStyle(color: FinoraColors.textSecondary),
          ),
        ),
      );
    }

    final entries = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Color colorFor(String categoryId) =>
        categoriesById[categoryId] != null ? Color(categoriesById[categoryId]!.color) : _fallbackCategoryColor;
    String nameFor(String categoryId) => categoriesById[categoryId]?.name ?? 'Otros';

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: [
                    for (final e in entries)
                      PieChartSectionData(
                        value: e.value / 100,
                        color: colorFor(e.key),
                        showTitle: false,
                      ),
                  ],
                  centerSpaceRadius: 70,
                  sectionsSpace: 2,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Total del mes',
                    style: TextStyle(color: FinoraColors.textSecondary, fontSize: 12),
                  ),
                  Text(
                    formatMoney(totalCents),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final e in entries)
          _CategoryLegendRow(
            color: colorFor(e.key),
            name: nameFor(e.key),
            cents: e.value,
            percent: ((e.value / totalCents) * 100).round(),
          ),
      ],
    );
  }
}

class _CategoryLegendRow extends StatelessWidget {
  const _CategoryLegendRow({
    required this.color,
    required this.name,
    required this.cents,
    required this.percent,
  });
  final Color color;
  final String name;
  final int cents;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(name)),
          Text(formatMoney(cents), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            child: Text(
              '$percent%',
              textAlign: TextAlign.right,
              style: const TextStyle(color: FinoraColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barras "Evolución mensual": dos barras por mes (gasto rojo, ingreso
/// verde), eje X con las iniciales del mes en español.
class _MonthlyBarChart extends StatelessWidget {
  const _MonthlyBarChart({required this.series});
  final List<_MonthPoint> series;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= series.length) return const SizedBox.shrink();
                  final label = _capitalize(DateFormat.MMM('es').format(series[i].month));
                  return SideTitleWidget(meta: meta, child: Text(label));
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < series.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: series[i].expense / 100,
                    color: FinoraColors.expense,
                    width: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  BarChartRodData(
                    toY: series[i].income / 100,
                    color: FinoraColors.income,
                    width: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BarLegend extends StatelessWidget {
  const _BarLegend();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendDot(color: FinoraColors.expense, label: 'Gastos'),
        SizedBox(width: 16),
        _LegendDot(color: FinoraColors.income, label: 'Ingresos'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: FinoraColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}
