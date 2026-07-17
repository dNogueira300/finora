import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import 'due_dates.dart';

final _activeAccountsProvider = StreamProvider.autoDispose<List<Account>>((ref) {
  return ref.watch(databaseProvider).accountsDao.watchActive();
});

/// Un vencimiento de una cuenta de credito: `kind` es 'pago' (`paymentDueDay`,
/// punto rojo) o 'cierre' (`statementDay`, punto ambar).
typedef _DueEntry = ({Account account, String kind, DateTime date});

const _weekdayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Pantalla "Calendario de vencimientos" (referencia Stitch "Calendario de
/// Vencimientos"): grid mensual navegable (chevrons) con los dias de pago
/// (rojo) y cierre (ambar) de las cuentas `credit` activas, y debajo la
/// lista "Próximos vencimientos" ordenada por fecha con los dias restantes.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    final today = toLima(DateTime.now().toUtc());
    _displayedMonth = DateTime(today.year, today.month, 1);
  }

  void _changeMonth(int delta) {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(_activeAccountsProvider);
    final today = toLima(DateTime.now().toUtc());
    final todayDate = DateTime(today.year, today.month, today.day);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendario de vencimientos')),
      body: SafeArea(
        child: accountsAsync.when(
          data: (accounts) {
            final creditAccounts = accounts.where((a) => a.type == 'credit').toList();
            final upcoming = _upcomingEntries(creditAccounts, todayDate);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _MonthHeader(
                  month: _displayedMonth,
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                ),
                const SizedBox(height: 12),
                _MonthGrid(
                  month: _displayedMonth,
                  accounts: creditAccounts,
                  today: todayDate,
                ),
                const SizedBox(height: 8),
                const _Legend(),
                const SizedBox(height: 24),
                Text('Próximos vencimientos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (upcoming.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No tienes tarjetas de crédito con fechas de pago o\ncierre configuradas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: FinoraColors.textSecondary),
                      ),
                    ),
                  )
                else
                  for (final entry in upcoming) _DueTile(entry: entry, today: todayDate),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('No se pudo cargar: $e')),
        ),
      ),
    );
  }
}

/// Vencimientos (pago + cierre) de [accounts], ordenados por fecha ascendente
/// usando `nextDueDate` a partir de [today].
List<_DueEntry> _upcomingEntries(List<Account> accounts, DateTime today) {
  final entries = <_DueEntry>[];
  for (final a in accounts) {
    final dueDay = a.paymentDueDay;
    if (dueDay != null) {
      entries.add((account: a, kind: 'pago', date: nextDueDate(dueDay, today)));
    }
    final statementDay = a.statementDay;
    if (statementDay != null) {
      entries.add((account: a, kind: 'cierre', date: nextDueDate(statementDay, today)));
    }
  }
  entries.sort((a, b) => a.date.compareTo(b.date));
  return entries;
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.onPrevious, required this.onNext});
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMMM yyyy', 'es').format(month);
    final capitalized = label.isEmpty ? label : label[0].toUpperCase() + label.substring(1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mes anterior',
          onPressed: onPrevious,
        ),
        Text(capitalized, style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Mes siguiente',
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Grid mensual de 7 columnas construido a mano con `DateTime` (sin paquetes
/// externos de calendario). Cada dia con vencimiento en [month] muestra un
/// punto rojo (pago) y/o ambar (cierre); el dia se ajusta ("clamp") al
/// ultimo dia del mes si `paymentDueDay`/`statementDay` no existen en un mes
/// corto (p. ej. dia 31 en un mes de 30 dias).
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.accounts, required this.today});
  final DateTime month;
  final List<Account> accounts;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=lunes..7=domingo
    final leadingBlanks = firstWeekday - 1;

    final paymentDays = <int>{};
    final statementDays = <int>{};
    for (final a in accounts) {
      final dueDay = a.paymentDueDay;
      if (dueDay != null) paymentDays.add(dueDay > lastDay ? lastDay : dueDay);
      final statementDay = a.statementDay;
      if (statementDay != null) {
        statementDays.add(statementDay > lastDay ? lastDay : statementDay);
      }
    }

    final isCurrentMonth = today.year == month.year && today.month == month.month;

    return Column(
      children: [
        Row(
          children: [
            for (final label in _weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: FinoraColors.textSecondary),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisExtent: 44),
          itemCount: leadingBlanks + lastDay,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = index - leadingBlanks + 1;
            final isToday = isCurrentMonth && day == today.day;
            final hasPayment = paymentDays.contains(day);
            final hasStatement = statementDays.contains(day);
            return Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: isToday ? Border.all(color: FinoraColors.primary, width: 2) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$day'),
                  if (hasPayment || hasStatement)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasPayment) const _Dot(color: FinoraColors.expense),
                        if (hasStatement) const _Dot(color: FinoraColors.warning),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _LegendDot(color: FinoraColors.expense, label: 'Pago'),
        SizedBox(width: 16),
        _LegendDot(color: FinoraColors.warning, label: 'Cierre'),
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

/// Fila de la lista "Próximos vencimientos": punto de color, nombre de la
/// cuenta, tipo de vencimiento (Pago/Cierre) con su fecha, y dias restantes
/// ("Vence en 5 días"/"Vence hoy").
class _DueTile extends StatelessWidget {
  const _DueTile({required this.entry, required this.today});
  final _DueEntry entry;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final days = entry.date.difference(today).inDays;
    final label = days <= 0 ? 'Vence hoy' : 'Vence en $days día${days == 1 ? '' : 's'}';
    final isPago = entry.kind == 'pago';
    final dotColor = isPago ? FinoraColors.expense : FinoraColors.warning;
    final kindLabel = isPago ? 'Pago' : 'Cierre';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        title: Text(entry.account.name),
        subtitle: Text('$kindLabel · ${DateFormat('d MMMM', 'es').format(entry.date)}'),
        trailing: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
