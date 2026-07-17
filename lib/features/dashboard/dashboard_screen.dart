import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import 'widgets/summary_card.dart';
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
    final greeting = localPart == null || localPart.isEmpty ? 'Hola 👋' : 'Hola, $localPart 👋';

    final syncStatus = ref.watch(syncStatusProvider);
    final txnsAsync = ref.watch(recentTxnsProvider);
    final categories = ref.watch(categoriesMapProvider);
    final totalsAsync = ref.watch(monthTotalsProvider);
    final balanceAsync = ref.watch(totalBalanceProvider);
    final totals = totalsAsync.valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(greeting, style: Theme.of(context).textTheme.titleLarge),
                ),
                _SyncIndicator(status: syncStatus),
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded),
                  tooltip: 'Alertas',
                  onPressed: () => context.push('/alerts'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _BalanceCard(cents: balanceAsync.valueOrNull ?? 0),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SummaryCard(
                    label: 'Ingresos del mes',
                    cents: totals?.incomeCents ?? 0,
                    color: FinoraColors.income,
                    icon: Icons.arrow_downward_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SummaryCard(
                    label: 'Gastos del mes',
                    cents: totals?.expenseCents ?? 0,
                    color: FinoraColors.expense,
                    icon: Icons.arrow_upward_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SummaryCard(
                    label: 'Ahorro',
                    cents: (totals?.incomeCents ?? 0) - (totals?.expenseCents ?? 0),
                    color: FinoraColors.savings,
                    icon: Icons.savings_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Transacciones recientes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.cents});
  final int cents;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FinoraColors.primary, FinoraColors.primaryDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saldo total', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            formatMoney(cents),
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
          ),
        ],
      ),
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
