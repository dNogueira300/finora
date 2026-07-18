import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../core/finora_tokens.dart';
import '../../core/finora_widgets.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import '../alerts/alerts_screen.dart';
import 'widgets/txn_tile.dart';

/// Las 10 transacciones mas recientes. Ademas de alimentar la lista de la
/// pantalla, se usa como "trigger" de recalculo por otros providers (ver
/// nota en `monthTotalsProvider`/`totalBalanceProvider`).
final recentTxnsProvider = StreamProvider.autoDispose<List<Txn>>((ref) {
  return ref.watch(databaseProvider).transactionsDao.watchRecent(10);
});

final _expenseCategoriesProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(databaseProvider).categoriesDao.watchByKind('expense');
});

final _incomeCategoriesProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(databaseProvider).categoriesDao.watchByKind('income');
});

/// Mapa id -> Category combinando ambos `kind` ('expense' e 'income'), que
/// es lo que `TxnTile` necesita para resolver icono/nombre/color de cada
/// transaccion. Se reconstruye automaticamente cada vez que cualquiera de
/// los dos streams de categorias emite (sin necesidad de combinar streams a
/// mano: Riverpod ya reconstruye este `Provider` al observar ambos).
final categoriesMapProvider = Provider.autoDispose<Map<String, Category>>((ref) {
  final expense = ref.watch(_expenseCategoriesProvider).valueOrNull ?? const [];
  final income = ref.watch(_incomeCategoriesProvider).valueOrNull ?? const [];
  return {for (final c in [...expense, ...income]) c.id: c};
});

final _activeAccountsProvider = StreamProvider.autoDispose<List<Account>>((ref) {
  return ref.watch(databaseProvider).accountsDao.watchActive();
});

final _goalsProvider = StreamProvider.autoDispose<List<SavingsGoal>>((ref) {
  return ref.watch(databaseProvider).goalsDao.watchAll();
});

/// Elige la meta a destacar en el card "Metas de ahorro": la de fecha limite
/// (`deadline`) mas proxima entre las que la tienen; si ninguna tiene fecha
/// limite, la primera del listado (regla determinista simple, ya que
/// `watchAll()` no garantiza un orden util quando todas las fechas son
/// nulas). Devuelve `null` solo si no hay ninguna meta.
SavingsGoal? nearestGoal(List<SavingsGoal> goals) {
  if (goals.isEmpty) return null;
  final withDeadline = goals.where((g) => g.deadline != null).toList()
    ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
  return withDeadline.isNotEmpty ? withDeadline.first : goals.first;
}

/// Totales del mes calendario actual (hora de Lima).
typedef MonthTotals = ({int expenseCents, int incomeCents});

/// NOTA sobre actualizacion en vivo: `monthlyTotal`/`balanceCents` son
/// consultas `Future` puntuales (no streams), asi que un `FutureProvider`
/// "puro" nunca se re-ejecutaria solo al insertar una transaccion nueva. En
/// vez de reescribir esas sumas como streams reactivos en Dart, ambos
/// providers de abajo hacen `ref.watch(recentTxnsProvider)` (que si es un
/// stream de drift) unicamente para que Riverpod los invalide cada vez que
/// cambian las transacciones recientes, y luego repiten la consulta con los
/// DAOs existentes. Limite conocido y aceptado para esta tarea: una edicion
/// a una transaccion fuera del top-10 mas reciente no dispara el recalculo.
final monthTotalsProvider = FutureProvider.autoDispose<MonthTotals>((ref) async {
  final db = ref.watch(databaseProvider);
  ref.watch(recentTxnsProvider);
  final now = toLima(DateTime.now().toUtc());
  final month = DateTime(now.year, now.month, 1);
  final expense = await db.transactionsDao.monthlyTotal(kind: 'expense', month: month);
  final income = await db.transactionsDao.monthlyTotal(kind: 'income', month: month);
  return (expenseCents: expense, incomeCents: income);
});

/// Suma de `balanceCents` de las cuentas activas cuyo `type != 'credit'`
/// ("Saldo total"). Ver nota de `monthTotalsProvider` sobre por que observa
/// `recentTxnsProvider`: aqui ademas depende de `_activeAccountsProvider`
/// para reaccionar si se crea/edita/archiva una cuenta.
final totalBalanceProvider = FutureProvider.autoDispose<int>((ref) async {
  final db = ref.watch(databaseProvider);
  ref.watch(recentTxnsProvider);
  final accounts = await ref.watch(_activeAccountsProvider.future);
  var total = 0;
  for (final a in accounts) {
    if (a.type == 'credit') continue;
    total += await db.accountsDao.balanceCents(a.id);
  }
  return total;
});

/// Email del usuario autenticado, o null si no hay sesion. Envuelto en
/// try/catch porque en tests de widgets no se llama a `Supabase.initialize()`
/// y `Supabase.instance` lanza un `AssertionError` en ese caso: se trata
/// igual que "sin sesion" en vez de propagar el error.
String? _currentUserEmail() {
  try {
    return Supabase.instance.client.auth.currentUser?.email;
  } on Object {
    return null;
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = _currentUserEmail();
    final localPart = email?.split('@').first;
    final greeting = localPart == null || localPart.isEmpty ? 'Hola' : 'Hola, $localPart';

    final syncStatus = ref.watch(syncStatusProvider);
    final txnsAsync = ref.watch(recentTxnsProvider);
    final categories = ref.watch(categoriesMapProvider);
    final totalsAsync = ref.watch(monthTotalsProvider);
    final balanceAsync = ref.watch(totalBalanceProvider);
    final totals = totalsAsync.valueOrNull;
    final goalsAsync = ref.watch(_goalsProvider);
    final unreadCount = ref.watch(unreadCountProvider).valueOrNull ?? 0;

    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: FinoraColors.background,
      body: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Cabecera de marca con degradado: saludo + campana y, en grande,
            // el saldo total estilo "wallet".
            BrandHeader(
              padding: EdgeInsets.zero,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  // Padding inferior generoso: la sheet se sube (Transform) y
                  // solapa el borde inferior del header sin tapar el monto.
                  padding: const EdgeInsets.fromLTRB(
                    FinoraTokens.s16,
                    FinoraTokens.s16,
                    FinoraTokens.s16,
                    FinoraTokens.s32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              greeting,
                              style: textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _SyncIndicator(status: syncStatus),
                          const SizedBox(width: FinoraTokens.s4),
                          Badge(
                            label: Text('$unreadCount'),
                            isLabelVisible: unreadCount > 0,
                            child: IconButton(
                              icon: const Icon(
                                Icons.notifications_none_rounded,
                                color: Colors.white,
                              ),
                              tooltip: 'Alertas',
                              onPressed: () => context.push('/alerts'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: FinoraTokens.s16),
                      const Text(
                        'Saldo total',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(height: FinoraTokens.s4),
                      Text(
                        formatMoney(balanceAsync.valueOrNull ?? 0),
                        style: textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // La sheet solapa el header subiendo el radio de sus esquinas.
            Transform.translate(
              offset: const Offset(0, -FinoraTokens.rSheet),
              child: ContentSheet(
                padding: const EdgeInsets.fromLTRB(
                  FinoraTokens.s16,
                  FinoraTokens.s24,
                  FinoraTokens.s16,
                  FinoraTokens.s24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Acciones rapidas.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Squircle(
                          icon: Icons.remove_circle_outline,
                          label: 'Agregar gasto',
                          highlighted: true,
                          onTap: () => context.push('/add'),
                        ),
                        Squircle(
                          icon: Icons.add_circle_outline,
                          label: 'Agregar ingreso',
                          onTap: () => context.push('/add'),
                        ),
                        Squircle(
                          icon: Icons.calendar_month_outlined,
                          label: 'Calendario',
                          onTap: () => context.push('/calendar'),
                        ),
                        Squircle(
                          icon: Icons.savings_outlined,
                          label: 'Metas',
                          onTap: () => context.go('/goals'),
                        ),
                      ],
                    ),
                    const SizedBox(height: FinoraTokens.s24),
                    // 2. Resumen del mes.
                    const SectionHeader('Resumen del mes'),
                    const SizedBox(height: FinoraTokens.s12),
                    _MonthSummaryCard(
                      incomeCents: totals?.incomeCents ?? 0,
                      expenseCents: totals?.expenseCents ?? 0,
                    ),
                    const SizedBox(height: FinoraTokens.s24),
                    // 3. Movimientos recientes.
                    const SectionHeader('Movimientos recientes'),
                    const SizedBox(height: FinoraTokens.s8),
                    txnsAsync.when(
                      data: (txns) {
                        if (txns.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                'Registra tu primer gasto con el botón +',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: FinoraColors.textSecondary),
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final txn in txns)
                              TxnTile(txn: txn, category: categories[txn.categoryId]),
                          ],
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: Text('No se pudo cargar: $e')),
                      ),
                    ),
                    const SizedBox(height: FinoraTokens.s16),
                    // 4. Metas de ahorro.
                    _GoalsCard(goal: nearestGoal(goalsAsync.valueOrNull ?? const [])),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card unica "Resumen del mes": tres indicadores (ingresos, gastos y
/// balance del mes) en una fila, separados por divisores verticales y con los
/// montos coloreados segun su significado.
class _MonthSummaryCard extends StatelessWidget {
  const _MonthSummaryCard({required this.incomeCents, required this.expenseCents});
  final int incomeCents;
  final int expenseCents;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FinoraTokens.rCard),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: FinoraTokens.s16,
          horizontal: FinoraTokens.s8,
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'Ingresos',
                  cents: incomeCents,
                  color: FinoraColors.income,
                ),
              ),
              const VerticalDivider(width: 1, color: FinoraColors.border),
              Expanded(
                child: _SummaryItem(
                  label: 'Gastos',
                  cents: expenseCents,
                  color: FinoraColors.expense,
                ),
              ),
              const VerticalDivider(width: 1, color: FinoraColors.border),
              Expanded(
                child: _SummaryItem(
                  label: 'Balance',
                  cents: incomeCents - expenseCents,
                  color: FinoraColors.savings,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.cents, required this.color});
  final String label;
  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: FinoraColors.textSecondary),
        ),
        const SizedBox(height: FinoraTokens.s4),
        Text(
          formatMoney(cents),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Card "Metas de ahorro" del dashboard: muestra la meta mas proxima a
/// vencer (ver `nearestGoal`) con su barra de progreso, o una invitacion a
/// crear la primera meta si todavia no hay ninguna. Se mantiene visible
/// siempre (no se oculta con 0 metas) para que el enlace a `/goals` este
/// disponible desde el dashboard en cualquier estado, igual que el resto de
/// cards de esta pantalla.
class _GoalsCard extends StatelessWidget {
  const _GoalsCard({required this.goal});
  final SavingsGoal? goal;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FinoraTokens.rCard),
      ),
      child: InkWell(
        onTap: () => context.go('/goals'),
        child: Padding(
          padding: const EdgeInsets.all(FinoraTokens.s16),
          child: goal == null ? _buildEmpty(context) : _buildGoal(context, goal!),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          backgroundColor: FinoraColors.savings,
          radius: 16,
          child: Icon(Icons.savings_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Metas de ahorro', style: Theme.of(context).textTheme.titleMedium),
              const Text('Crea tu primera meta', style: TextStyle(color: FinoraColors.textSecondary)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: FinoraColors.textSecondary),
      ],
    );
  }

  Widget _buildGoal(BuildContext context, SavingsGoal g) {
    final ratio = g.targetCents > 0 ? (g.savedCents / g.targetCents).clamp(0.0, 1.0) : 0.0;
    final percent = (ratio * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CircleAvatar(
              backgroundColor: FinoraColors.savings,
              radius: 16,
              child: Icon(Icons.savings_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Metas de ahorro', style: Theme.of(context).textTheme.titleMedium),
            ),
            Text('$percent%',
                style: const TextStyle(fontWeight: FontWeight.w700, color: FinoraColors.income)),
            const Icon(Icons.chevron_right, color: FinoraColors.textSecondary),
          ],
        ),
        const SizedBox(height: 8),
        Text(g.name, style: const TextStyle(color: FinoraColors.textSecondary)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: FinoraColors.border,
            valueColor: const AlwaysStoppedAnimation(FinoraColors.income),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${formatMoney(g.savedCents)} de ${formatMoney(g.targetCents)}',
          style: const TextStyle(color: FinoraColors.textSecondary),
        ),
      ],
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({required this.status});
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      SyncStatus.idle => (Icons.cloud_done, FinoraColors.income),
      SyncStatus.syncing => (Icons.sync, FinoraColors.secondary),
      SyncStatus.offline => (Icons.cloud_off, FinoraColors.textSecondary),
      SyncStatus.error => (Icons.cloud_off, FinoraColors.expense),
    };
    return Icon(icon, color: color);
  }
}
