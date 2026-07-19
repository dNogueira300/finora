import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../core/finora_tokens.dart';
import '../../core/finora_widgets.dart';
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'goals-new-fab',
        onPressed: () => _openEditSheet(context),
        backgroundColor: FinoraColors.primary,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        label: const Text(
          '+ Nueva meta',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: BrandPage(
        title: 'Metas de ahorro',
        child: goalsAsync.when(
          data: (goals) {
            if (goals.isEmpty) return const _EmptyState();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [for (final g in goals) _GoalCard(goal: g)],
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
Future<void> _addContribution(WidgetRef ref, SavingsGoal g, int cents) => ref
    .read(databaseProvider)
    .goalsDao
    .upsert(
      SavingsGoalsCompanion(
        id: Value(g.id),
        name: Value(g.name),
        targetCents: Value(g.targetCents),
        savedCents: Value(g.savedCents + cents),
        deadline: Value(g.deadline),
        color: Value(g.color),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );

/// Dialogo "Abonar": pide un monto y lo suma a `savedCents`. Distingue
/// cancelar (el dialogo devuelve `null`) de un monto invalido (el dialogo
/// devuelve el texto crudo, que no parsea a un entero positivo) para mostrar
/// el SnackBar "Monto inválido" solo en el segundo caso, mismo patron que
/// `add_transaction_screen._save`.
Future<void> _showContributeDialog(
  BuildContext context,
  WidgetRef ref,
  SavingsGoal goal,
) async {
  final input = await showDialog<String>(
    context: context,
    builder: (ctx) => _ContributeDialog(goalName: goal.name),
  );
  if (input == null) return; // cancelado

  final cents = parseMoney(input);
  if (cents == null || cents <= 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Monto inválido')));
    }
    return;
  }
  await _addContribution(ref, goal, cents);
}

/// Contenido del dialogo "Abonar", extraido a un `StatefulWidget` propio
/// para que el `TextEditingController` del monto se cree y se libere junto
/// con el ciclo de vida del `State` (`dispose()`), en vez de con el
/// `Future` de `showDialog` (que se completa apenas se llama a
/// `Navigator.pop`, ANTES de que termine la animacion de salida del
/// dialogo: liberar el controller en ese momento lo deja "usado tras
/// dispose" mientras el `TextField` todavia esta en el arbol durante esa
/// animacion).
class _ContributeDialog extends StatefulWidget {
  const _ContributeDialog({required this.goalName});
  final String goalName;

  @override
  State<_ContributeDialog> createState() => _ContributeDialogState();
}

class _ContributeDialogState extends State<_ContributeDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Abonar a "${widget.goalName}"'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Monto',
          prefixText: 'S/ ',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Abonar'),
        ),
      ],
    );
  }
}

/// Menu de acciones de una meta (Editar/Eliminar). Publica (sin `_`) para
/// poder invocarla directamente desde los tests de widget, mismo patron que
/// `showAccountMenu` en `cards_screen.dart`.
Future<void> showGoalMenu(
  BuildContext context,
  WidgetRef ref,
  SavingsGoal goal,
) async {
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
            leading: const Icon(
              Icons.delete_outline,
              color: FinoraColors.expense,
            ),
            title: const Text(
              'Eliminar',
              style: TextStyle(color: FinoraColors.expense),
            ),
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
          content: Text(
            '¿Eliminar "${goal.name}"? Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Eliminar',
                style: TextStyle(color: FinoraColors.expense),
              ),
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
        padding: const EdgeInsets.all(FinoraTokens.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.savings_outlined,
              size: 48,
              color: FinoraColors.textSecondary,
            ),
            const SizedBox(height: FinoraTokens.s12),
            Text(
              'Aún no tienes metas.\nToca "Nueva meta" para crear la primera.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: FinoraColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de una meta: dot + nombre + porcentaje (en el color de la meta),
/// barra de progreso alta con relleno del color de la meta, monto ahorrado
/// (en negrita) "de" objetivo, fecha limite (si tiene) y "Abonar" + menu.
class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});
  final SavingsGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(goal.color);
    final ratio = goal.targetCents > 0
        ? (goal.savedCents / goal.targetCents).clamp(0.0, 1.0)
        : 0.0;
    final percent = (ratio * 100).round();

    return Card(
      margin: const EdgeInsets.only(bottom: FinoraTokens.s12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FinoraTokens.rCard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FinoraTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: FinoraTokens.s8),
                Expanded(
                  child: Text(
                    goal.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$percent%',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Más opciones',
                  onPressed: () => showGoalMenu(context, ref, goal),
                ),
              ],
            ),
            const SizedBox(height: FinoraTokens.s8),
            ClipRRect(
              borderRadius: BorderRadius.circular(FinoraTokens.rPill),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                backgroundColor: FinoraColors.border,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: FinoraTokens.s8),
            Text.rich(
              TextSpan(
                style: const TextStyle(color: FinoraColors.textSecondary),
                children: [
                  TextSpan(
                    text: formatMoney(goal.savedCents),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' de ${formatMoney(goal.targetCents)}'),
                ],
              ),
            ),
            if (goal.deadline != null) ...[
              const SizedBox(height: FinoraTokens.s4),
              Row(
                children: [
                  const Icon(
                    Icons.event,
                    size: 14,
                    color: FinoraColors.textSecondary,
                  ),
                  const SizedBox(width: FinoraTokens.s4),
                  Text(
                    DateFormat(
                      'd MMMM yyyy',
                      'es',
                    ).format(toLima(goal.deadline!)),
                    style: const TextStyle(
                      color: FinoraColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: FinoraTokens.s12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => _showContributeDialog(context, ref, goal),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                child: const Text('Abonar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
