import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/category_icons.dart';
import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import '../../services/notifications_service.dart';
import '../alerts/spending_limit_watcher.dart';
import '../settings/settings_screen.dart' show currentUserIdProvider;

/// Categorias del `kind` actualmente seleccionado (gasto/ingreso). Se define
/// como `family` local a esta pantalla (autoDispose) siguiendo la misma
/// convencion que los providers privados de `dashboard_screen.dart`.
final _categoriesByKindProvider =
    StreamProvider.autoDispose.family<List<Category>, String>((ref, kind) {
  return ref.watch(databaseProvider).categoriesDao.watchByKind(kind);
});

final _activeAccountsProvider = StreamProvider.autoDispose<List<Account>>((ref) {
  return ref.watch(databaseProvider).accountsDao.watchActive();
});

const _accountTypeLabels = {
  'cash': 'Efectivo',
  'wallet': 'Billetera',
  'debit': 'Débito',
  'credit': 'Crédito',
};

String _accountTypeLabel(String type) => _accountTypeLabels[type] ?? type;

/// Pantalla de alta de una transaccion (gasto o ingreso). Referencia Stitch
/// "Nuevo Gasto Premium": toggle Gasto/Ingreso, monto grande centrado,
/// categorias en chips, cuenta en dropdown, fecha (default hoy en hora de
/// Lima) y nota opcional.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  String _kind = 'expense';
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _selectedCategoryId;
  String? _selectedAccountId;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    // `_date` se maneja siempre en hora de Lima ("naive"); se convierte a
    // UTC unicamente al persistir (ver `_save`).
    _date = toLima(DateTime.now().toUtc());
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('es'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final cents = parseMoney(_amountCtrl.text);
    if (cents == null || cents <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Monto inválido')));
      return;
    }
    if (_selectedCategoryId == null || _selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona una categoría y una cuenta')));
      return;
    }
    await ref.read(databaseProvider).transactionsDao.insertTxn(
          TransactionsCompanion.insert(
            id: const Uuid().v4(),
            accountId: _selectedAccountId!,
            categoryId: _selectedCategoryId!,
            kind: _kind,
            amountCents: cents,
            note: Value(_noteCtrl.text.isEmpty ? null : _noteCtrl.text),
            occurredAt: limaToUtc(_date),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    if (_kind == 'expense') {
      // Mejor esfuerzo (Task 23), mismo criterio que
      // `rescheduleCardRemindersFromDb` (Task 22): revisar el limite de
      // gasto mensual tras guardar un gasto no debe bloquear el
      // guardado/cierre de esta pantalla si algo falla (sin sesion, sin
      // limite configurado, plugin de notificaciones no disponible como en
      // los tests de widgets).
      try {
        final userId = ref.read(currentUserIdProvider);
        if (userId != null) {
          await checkSpendingLimit(
            ref.read(databaseProvider),
            ref.read(notificationsServiceProvider),
            userId,
          );
        }
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = _kind == 'expense';
    final kindColor = isExpense ? FinoraColors.expense : FinoraColors.income;
    final categoriesAsync = ref.watch(_categoriesByKindProvider(_kind));
    final accountsAsync = ref.watch(_activeAccountsProvider);
    final accounts = accountsAsync.valueOrNull ?? const [];
    final noAccounts = accountsAsync.hasValue && accounts.isEmpty;
    final selectedAccountId =
        accounts.any((a) => a.id == _selectedAccountId) ? _selectedAccountId : null;

    return Scaffold(
      appBar: AppBar(title: Text(isExpense ? 'Nuevo gasto' : 'Nuevo ingreso')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'expense',
                    label: Text('Gasto'),
                    icon: Icon(Icons.arrow_upward_rounded),
                  ),
                  ButtonSegment(
                    value: 'income',
                    label: Text('Ingreso'),
                    icon: Icon(Icons.arrow_downward_rounded),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) => setState(() {
                  _kind = selection.first;
                  // La categoria seleccionada pertenece al `kind` anterior:
                  // se limpia para forzar una nueva eleccion valida.
                  _selectedCategoryId = null;
                }),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: kindColor,
                  selectedForegroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(fontWeight: FontWeight.w700, color: kindColor),
              decoration: const InputDecoration(
                hintText: 'S/ 0.00',
                border: InputBorder.none,
                filled: false,
              ),
            ),
            const SizedBox(height: 24),
            Text('Categoría', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            categoriesAsync.when(
              data: (categories) {
                if (categories.isEmpty) {
                  return const Text(
                    'No hay categorías para este tipo todavía.',
                    style: TextStyle(color: FinoraColors.textSecondary),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in categories)
                      ChoiceChip(
                        label: Text(c.name),
                        avatar: Icon(
                          categoryIcons[c.icon] ?? Icons.category,
                          size: 18,
                          color: _selectedCategoryId == c.id ? Colors.white : Color(c.color),
                        ),
                        selected: _selectedCategoryId == c.id,
                        selectedColor: Color(c.color),
                        labelStyle: TextStyle(
                          color: _selectedCategoryId == c.id ? Colors.white : null,
                        ),
                        onSelected: (_) => setState(() => _selectedCategoryId = c.id),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('No se pudo cargar categorías: $e'),
            ),
            const SizedBox(height: 24),
            Text('Cuenta', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (noAccounts)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FinoraColors.warning.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: FinoraColors.warning),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Crea una cuenta primero en Mis tarjetas'),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: selectedAccountId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: const Text('Selecciona una cuenta'),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.name} (${_accountTypeLabel(a.type)})'),
                    ),
                ],
                onChanged: (v) => setState(() => _selectedAccountId = v),
              ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Fecha'),
              subtitle: Text(DateFormat('d MMMM yyyy', 'es').format(_date)),
              onTap: _pickDate,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: noAccounts ? null : _save,
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
