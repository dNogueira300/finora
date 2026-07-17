import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import 'edit_goal_sheet.dart';

final _goalsProvider = StreamProvider.autoDispose<List<SavingsGoal>>((ref) {
  return ref.watch(databaseProvider).goalsDao.watchAll();
});

/// Pantalla "Metas de ahorro" (Task 19): lista de metas con barra de
/// progreso (`saved/target`), boton "Abonar" por meta y menu Editar/
/// Eliminar. FAB "+ Nueva meta" abre `EditGoalSheet` para crear una meta.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(_goalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Metas de ahorro')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditSheet(context),
        backgroundColor: FinoraColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nueva meta', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: goalsAsync.when(
          data: (goals) {
            if (goals.isEmpty) return const _EmptyState();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final g in goals) _GoalCard(goal: g),
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

Future<void> _openEditSheet(BuildContext context, {SavingsGoal? goal}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EditGoalSheet(goal: goal),
  );
}

/// Registra un abono: suma `cents` a `savedCents` reenviando el resto de la
/// fila tal cual (ver nota de `upsert`/`insertOnConflictUpdate` en
/// `goals_dao.dart`: valida columnas NOT NULL como si fuera un INSERT nuevo
/// aunque la fila ya exista).
Future<void> _addContribution(WidgetRef ref, SavingsGoal g, int cents) =>
    ref.read(databaseProvider).goalsDao.upsert(SavingsGoalsCompanion(
          id: Value(g.id),
          name: Value(g.name),
          targetCents: Value(g.targetCents),
          savedCents: Value(g.savedCents + cents),
          deadline: Value(g.deadline),
          color: Value(g.color),
          updatedAt: Value(DateTime.now().toUtc()),
        ));

/// Dialogo "Abonar": pide un monto y lo suma a `savedCents`. Distingue
/// cancelar (el dialogo devuelve `null`) de un monto invalido (el dialogo
/// devuelve el texto crudo, que no parsea a un entero positivo) para mostrar
/// el SnackBar "Monto inválido" solo en el segundo caso, mismo patron que
/// `add_transaction_screen._save`.
Future<void> _showContributeDialog(BuildContext context, WidgetRef ref, SavingsGoal goal) async {
  final ctrl = TextEditingController();
  final input = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Abonar a "${goal.name}"'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Monto',
          prefixText: 'S/ ',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text),
          child: const Text('Abonar'),
        ),
      ],
    ),
  );
  if (input == null) return; // cancelado

  final cents = parseMoney(input);
  if (cents == null || cents <= 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Monto inválido')));
    }
    return;
  }
  await _addContribution(ref, goal, cents);
}

/// Menu de acciones de una meta (Editar/Eliminar). Publica (sin `_`) para
/// poder invocarla directamente desde los tests de widget, mismo patron que
/// `showAccountMenu` en `cards_screen.dart`.
Future<void> showGoalMenu(BuildContext context, WidgetRef ref, SavingsGoal goal) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar'),
            onTap: () => Navigator.of(ctx).pop('edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: FinoraColors.expense),
            title: const Text('Eliminar', style: TextStyle(color: FinoraColors.expense)),
            onTap: () => Navigator.of(ctx).pop('delete'),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;
  switch (action) {
    case 'edit':
      await _openEditSheet(context, goal: goal);
    case 'delete':
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eliminar meta'),
          content: Text('¿Eliminar "${goal.name}"? Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Eliminar', style: TextStyle(color: FinoraColors.expense)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ref.read(databaseProvider).goalsDao.softDelete(goal.id);
      }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Aún no tienes metas.\nToca "Nueva meta" para crear la primera.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: FinoraColors.textSecondary),
        ),
      ),
    );
  }
}

/// Card de una meta: nombre, porcentaje, barra de progreso verde, monto
/// ahorrado/objetivo, fecha limite (si tiene) y botones "Abonar" + menu.
class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});
  final SavingsGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratio =
        goal.targetCents > 0 ? (goal.savedCents / goal.targetCents).clamp(0.0, 1.0) : 0.0;
    final percent = (ratio * 100).round();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Color(goal.color),
                  radius: 16,
                  child: const Icon(Icons.savings_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(goal.name, style: Theme.of(context).textTheme.titleMedium),
                ),
                Text('$percent%',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: FinoraColors.income)),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Más opciones',
                  onPressed: () => showGoalMenu(context, ref, goal),
                ),
              ],
            ),
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
              '${formatMoney(goal.savedCents)} ahorrado de ${formatMoney(goal.targetCents)}',
              style: const TextStyle(color: FinoraColors.textSecondary),
            ),
            if (goal.deadline != null) ...[
              const SizedBox(height: 4),
              Text(
                'Fecha límite: ${DateFormat('d MMMM yyyy', 'es').format(toLima(goal.deadline!))}',
                style: const TextStyle(color: FinoraColors.textSecondary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _showContributeDialog(context, ref, goal),
                child: const Text('Abonar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
