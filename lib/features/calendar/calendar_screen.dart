import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../core/finora_tokens.dart';
import '../../core/finora_widgets.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import 'due_dates.dart';

final _activeAccountsProvider = StreamProvider.autoDispose<List<Account>>((
  ref,
) {
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
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + delta,
        1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(_activeAccountsProvider);
    final today = toLima(DateTime.now().toUtc());
    final todayDate = DateTime(today.year, today.month, today.day);

    return Scaffold(
      body: BrandPage(
        title: 'Calendario de vencimientos',
        child: accountsAsync.when(
          data: (accounts) {
            final creditAccounts = accounts
                .where((a) => a.type == 'credit')
                .toList();
            final upcoming = _upcomingEntries(creditAccounts, todayDate);
            return ListView(
              padding: const EdgeInsets.all(FinoraTokens.s16),
              children: [
                _MonthHeader(
                  month: _displayedMonth,
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                ),
                const SizedBox(height: FinoraTokens.s12),
                _MonthGrid(
                  month: _displayedMonth,
                  accounts: creditAccounts,
                  today: todayDate,
                ),
                const SizedBox(height: FinoraTokens.s8),
                const _Legend(),
                const SizedBox(height: FinoraTokens.s24),
                const SectionHeader('Próximos vencimientos'),
                const SizedBox(height: FinoraTokens.s8),
                if (upcoming.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: FinoraTokens.s32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_available,
                            size: 48,
                            color: FinoraColors.textSecondary,
                          ),
                          SizedBox(height: FinoraTokens.s12),
                          Text(
                            'No tienes tarjetas de crédito con fechas de pago o cierre configuradas.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: FinoraColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final entry in upcoming)
                    _DueTile(entry: entry, today: todayDate),
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
      entries.add((
        account: a,
        kind: 'cierre',
        date: nextDueDate(statementDay, today),
      ));
    }
  }
  entries.sort((a, b) => a.date.compareTo(b.date));
  return entries;
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMMM yyyy', 'es').format(month);
    final capitalized = label.isEmpty
        ? label
        : label[0].toUpperCase() + label.substring(1);
    return Container(
      decoration: BoxDecoration(
        color: FinoraColors.surface,
        borderRadius: BorderRadius.circular(FinoraTokens.rPill),
        boxShadow: FinoraTokens.shadowSoft,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: FinoraTokens.s8,
        vertical: FinoraTokens.s4,
      ),
      child: Row(
        children: [
          _ChevronButton(
            icon: Icons.chevron_left,
            tooltip: 'Mes anterior',
            onPressed: onPrevious,
          ),
          Expanded(
            child: Text(
              capitalized,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: FinoraColors.textPrimary,
              ),
            ),
          ),
          _ChevronButton(
            icon: Icons.chevron_right,
            tooltip: 'Mes siguiente',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// Boton de navegacion de mes: chevron circular con ripple sobre un fondo
/// suave, dentro del card pill de [_MonthHeader].
class _ChevronButton extends StatelessWidget {
  const _ChevronButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      color: FinoraColors.textPrimary,
      style: IconButton.styleFrom(
        backgroundColor: FinoraColors.background,
        shape: const CircleBorder(),
      ),
    );
  }
}

/// Grid mensual de 7 columnas construido a mano con `DateTime` (sin paquetes
/// externos de calendario). Cada dia con vencimiento en [month] muestra un
/// punto rojo (pago) y/o ambar (cierre); el dia se ajusta ("clamp") al
/// ultimo dia del mes si `paymentDueDay`/`statementDay` no existen en un mes
/// corto (p. ej. dia 31 en un mes de 30 dias).
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.accounts,
    required this.today,
  });
  final DateTime month;
  final List<Account> accounts;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(
      month.year,
      month.month,
      1,
    ).weekday; // 1=lunes..7=domingo
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

    final isCurrentMonth =
        today.year == month.year && today.month == month.month;

    return Column(
      children: [
        Row(
          children: [
            for (final label in _weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: FinoraColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: FinoraTokens.s4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 44,
          ),
          itemCount: leadingBlanks + lastDay,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = index - leadingBlanks + 1;
            final isToday = isCurrentMonth && day == today.day;
            final hasPayment = paymentDays.contains(day);
            final hasStatement = statementDays.contains(day);
            return Padding(
              padding: const EdgeInsets.all(2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? const BoxDecoration(
                            color: FinoraColors.primary,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: isToday
                            ? Colors.white
                            : FinoraColors.textPrimary,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Reserva fija de 6px para que las celdas con y sin
                  // vencimiento mantengan la misma altura y alineacion.
                  SizedBox(
                    height: 6,
                    child: (hasPayment || hasStatement)
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasPayment)
                                const _Dot(color: FinoraColors.expense),
                              if (hasStatement)
                                const _Dot(color: FinoraColors.warning),
                            ],
                          )
                        : null,
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
      width: 6,
      height: 6,
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
        SizedBox(width: FinoraTokens.s16),
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
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: FinoraColors.textSecondary,
            fontSize: 12,
          ),
        ),
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
    final label = days <= 0
        ? 'Vence hoy'
        : 'Vence en $days día${days == 1 ? '' : 's'}';
    final isPago = entry.kind == 'pago';
    final color = isPago ? FinoraColors.expense : FinoraColors.warning;
    final icon = isPago ? Icons.payments : Icons.event_note;
    final kindLabel = isPago ? 'Pago' : 'Cierre';
    return Card(
      margin: const EdgeInsets.only(bottom: FinoraTokens.s12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FinoraTokens.rCard),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(FinoraTokens.rInput),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(entry.account.name),
        subtitle: Text(
          '$kindLabel · ${DateFormat('d MMMM', 'es').format(entry.date)}',
        ),
        trailing: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
