import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../core/finora_tokens.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';

/// 8 colores predefinidos para el selector de color de metas, mismo patron
/// que `accountColorOptions` (Task 16) pero con el azul "ahorro" primero
/// porque es el default de la columna `SavingsGoals.color`.
const goalColorOptions = <int>[
  0xFF3B82F6, // ahorro (default)
  0xFF16A34A, // primario
  0xFF1E3A8A, // secundario
  0xFF8B5CF6, // inversión
  0xFFF59E0B, // alerta
  0xFFEF4444, // gasto
  0xFF0EA5E9, // celeste
  0xFFEC4899, // rosa
];

/// Bottom sheet de alta/edicion de una meta de ahorro (Task 19), mismas
/// convenciones que `EditAccountSheet` (Task 16): `Uuid().v4()` para altas,
/// `updatedAt` en UTC, selector de color entre 8 predefinidos.
///
/// Si `goal` es no-nulo, el formulario se pre-llena y `_save` reutiliza el
/// mismo `id` y conserva `savedCents` tal cual (el abono se hace aparte,
/// desde el dialogo "Abonar" de `GoalsScreen`); si es nulo, se crea una meta
/// nueva con `savedCents = 0`.
class EditGoalSheet extends ConsumerStatefulWidget {
  const EditGoalSheet({super.key, this.goal});
  final SavingsGoal? goal;

  @override
  ConsumerState<EditGoalSheet> createState() => _EditGoalSheetState();
}

class _EditGoalSheetState extends ConsumerState<EditGoalSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _targetCtrl;
  late int _color;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _nameCtrl = TextEditingController(text: g?.name ?? '');
    _targetCtrl =
        TextEditingController(text: g == null ? '' : (g.targetCents / 100).toStringAsFixed(2));
    _color = g?.color ?? goalColorOptions.first;
    // `deadline` se guarda en UTC; se convierte a hora de Lima ("naive")
    // para editar, igual que `_date` en `add_transaction_screen.dart`.
    _deadline = g?.deadline == null ? null : toLima(g!.deadline!);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? toLima(DateTime.now().toUtc()),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('es'),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ingresa un nombre')));
      return;
    }
    final targetCents = parseMoney(_targetCtrl.text);
    if (targetCents == null || targetCents <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ingresa un monto objetivo válido')));
      return;
    }

    final id = widget.goal?.id ?? const Uuid().v4();
    final savedCents = widget.goal?.savedCents ?? 0;
    await ref.read(databaseProvider).goalsDao.upsert(SavingsGoalsCompanion.insert(
          id: id,
          name: name,
          targetCents: targetCents,
          savedCents: Value(savedCents),
          deadline: Value(_deadline == null ? null : limaToUtc(_deadline!)),
          color: Value(_color),
          updatedAt: DateTime.now().toUtc(),
        ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: FinoraTokens.s16),
                decoration: BoxDecoration(
                  color: FinoraColors.border,
                  borderRadius: BorderRadius.circular(FinoraTokens.rPill),
                ),
              ),
            ),
            Text(
              widget.goal == null ? 'Nueva meta' : 'Editar meta',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _targetCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monto objetivo',
                prefixText: 'S/ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Fecha límite (opcional)'),
              subtitle: Text(
                _deadline == null ? 'Sin fecha límite' : DateFormat('d MMMM yyyy', 'es').format(_deadline!),
              ),
              onTap: _pickDeadline,
              trailing: _deadline == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Quitar fecha',
                      onPressed: () => setState(() => _deadline = null),
                    ),
            ),
            const SizedBox(height: 8),
            Text('Color', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in goalColorOptions)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: _color == c
                            ? Border.all(color: FinoraColors.textPrimary, width: 3)
                            : null,
                      ),
                      child: _color == c
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
                child: const Text('Guardar'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
