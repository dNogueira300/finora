import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/category_icons.dart';
import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../core/finora_snackbar.dart';
import '../../core/finora_tokens.dart';
import '../../core/finora_widgets.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import '../../services/notifications_service.dart';
import '../alerts/spending_limit_watcher.dart';
import '../categories/edit_category_sheet.dart';
import '../settings/settings_screen.dart' show currentUserIdProvider;

/// Categorias del `kind` actualmente seleccionado (gasto/ingreso). Se define
/// como `family` local a esta pantalla (autoDispose) siguiendo la misma
/// convencion que los providers privados de `dashboard_screen.dart`.
final _categoriesByKindProvider = StreamProvider.autoDispose
    .family<List<Category>, String>((ref, kind) {
      return ref.watch(databaseProvider).categoriesDao.watchByKind(kind);
    });

final _activeAccountsProvider = StreamProvider.autoDispose<List<Account>>((
  ref,
) {
  return ref.watch(databaseProvider).accountsDao.watchActive();
});

const _accountTypeLabels = {
  'cash': 'Efectivo',
  'wallet': 'Billetera',
  'debit': 'Débito',
  'credit': 'Crédito',
};

String _accountTypeLabel(String type) => _accountTypeLabels[type] ?? type;

/// Icono representativo del tipo de cuenta, para decorar el selector de cuenta
/// (mismo lenguaje visual que `cards_screen.dart`).
IconData _accountTypeIcon(String type) {
  switch (type) {
    case 'wallet':
      return Icons.account_balance_wallet_outlined;
    case 'debit':
      return Icons.credit_card_outlined;
    case 'credit':
      return Icons.credit_score_outlined;
    case 'cash':
    default:
      return Icons.payments_outlined;
  }
}

/// Pantalla de alta de una transaccion (gasto o ingreso). Referencia Stitch
/// "Nuevo Gasto Premium": toggle Gasto/Ingreso, monto grande centrado,
/// categorias en chips, cuenta en dropdown, fecha (default hoy en hora de
/// Lima) y nota opcional.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  String _kind = 'expense';
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  // El hint "S/ 0.00" del monto se oculta apenas el campo recibe foco (no
  // recien al escribir el primer digito): se observa el foco y se
  // reconstruye para quitar el hint.
  final _amountFocus = FocusNode();
  String? _selectedCategoryId;
  String? _selectedAccountId;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    // `_date` se maneja siempre en hora de Lima ("naive"); se convierte a
    // UTC unicamente al persistir (ver `_save`).
    _date = toLima(DateTime.now().toUtc());
    _amountFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _amountFocus.dispose();
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

  /// Abre el sheet de nueva categoria pre-seleccionando el `kind` actual y,
  /// si se creo una, la deja seleccionada (el sheet hace pop con su id).
  Future<void> _createCategory() async {
    final newId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EditCategorySheet(initialKind: _kind),
    );
    if (newId != null && mounted) {
      setState(() => _selectedCategoryId = newId);
    }
  }

  /// Menu de long-press sobre un chip de categoria: Editar (abre el sheet
  /// pre-llenado) o Eliminar (con confirmacion; soft delete para que el sync
  /// propague la baja). Si la categoria eliminada estaba seleccionada, se
  /// limpia la seleccion.
  Future<void> _showCategoryMenu(Category category) async {
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
    if (!mounted || action == null) return;

    switch (action) {
      case 'edit':
        await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => EditCategorySheet(category: category),
        );
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Eliminar categoría'),
            content: Text(
              '¿Eliminar "${category.name}"? Los movimientos ya registrados '
              'se mostrarán como "Sin categoría".',
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
        if (confirmed == true && mounted) {
          await ref
              .read(databaseProvider)
              .categoriesDao
              .softDelete(category.id);
          if (mounted && _selectedCategoryId == category.id) {
            setState(() => _selectedCategoryId = null);
          }
          if (mounted) FinoraSnackbar.success(context, 'Categoría eliminada');
        }
    }
  }

  Future<void> _editNote() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(initial: _noteCtrl.text),
    );
    if (result != null && mounted) {
      setState(() => _noteCtrl.text = result);
    }
  }

  Future<void> _save() async {
    final cents = parseMoney(_amountCtrl.text);
    if (cents == null || cents <= 0) {
      FinoraSnackbar.error(context, 'Monto inválido');
      return;
    }
    if (_selectedCategoryId == null || _selectedAccountId == null) {
      FinoraSnackbar.error(context, 'Selecciona una categoría y una cuenta');
      return;
    }
    await ref
        .read(databaseProvider)
        .transactionsDao
        .insertTxn(
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
    if (mounted) {
      FinoraSnackbar.success(context, 'Movimiento registrado');
      context.pop();
    }
  }

  /// Un lado del control segmentado doble (pill full-width). El lado
  /// seleccionado se rellena con [color] (expense/income) y texto blanco; el
  /// no seleccionado queda transparente con texto secundario. El
  /// [AnimatedContainer] anima el relleno y el [InkWell] da feedback de
  /// presion (ripple recortado al pill).
  Widget _kindSegment({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final selected = _kind == value;
    final fg = selected ? Colors.white : FinoraColors.textSecondary;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(FinoraTokens.rPill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() {
            _kind = value;
            // La categoria seleccionada pertenece al `kind` anterior: se
            // limpia para forzar una nueva eleccion valida.
            _selectedCategoryId = null;
          }),
          child: AnimatedContainer(
            duration: FinoraTokens.dFast,
            curve: FinoraTokens.curve,
            padding: const EdgeInsets.symmetric(vertical: FinoraTokens.s12),
            decoration: BoxDecoration(
              color: selected ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(FinoraTokens.rPill),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: FinoraTokens.s8),
                Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w700, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = _kind == 'expense';
    final kindColor = isExpense ? FinoraColors.expense : FinoraColors.income;
    final textTheme = Theme.of(context).textTheme;
    final categoriesAsync = ref.watch(_categoriesByKindProvider(_kind));
    final accountsAsync = ref.watch(_activeAccountsProvider);
    final accounts = accountsAsync.valueOrNull ?? const [];
    final noAccounts = accountsAsync.hasValue && accounts.isEmpty;
    final selectedAccountId = accounts.any((a) => a.id == _selectedAccountId)
        ? _selectedAccountId
        : null;
    Account? selectedAccount;
    for (final a in accounts) {
      if (a.id == selectedAccountId) {
        selectedAccount = a;
        break;
      }
    }

    return Scaffold(
      body: BrandPage(
        title: isExpense ? 'Nuevo gasto' : 'Nuevo ingreso',
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(FinoraTokens.s16),
                  children: [
                    // Control segmentado doble Gasto/Ingreso (pill full-width).
                    Container(
                      padding: const EdgeInsets.all(FinoraTokens.s4),
                      decoration: BoxDecoration(
                        color: FinoraColors.surface,
                        borderRadius: BorderRadius.circular(FinoraTokens.rPill),
                        border: Border.all(color: FinoraColors.border),
                      ),
                      child: Row(
                        children: [
                          _kindSegment(
                            value: 'expense',
                            label: 'Gasto',
                            icon: Icons.arrow_upward_rounded,
                            color: FinoraColors.expense,
                          ),
                          _kindSegment(
                            value: 'income',
                            label: 'Ingreso',
                            icon: Icons.arrow_downward_rounded,
                            color: FinoraColors.income,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FinoraTokens.s32),
                    // Monto protagonista: centrado, prefijo "S/" secundario,
                    // displayLarge en el color del `kind`, sin borde (solo un
                    // underline sutil al enfocar).
                    TextField(
                      controller: _amountCtrl,
                      focusNode: _amountFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      cursorColor: kindColor,
                      style: textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: kindColor,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: _amountFocus.hasFocus ? null : 'S/ 0.00',
                        hintStyle: textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: FinoraColors.textSecondary,
                        ),
                        prefixText: 'S/ ',
                        prefixStyle: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: FinoraColors.textSecondary,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: FinoraColors.border,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: FinoraTokens.s32),
                    Text('Categoría', style: textTheme.titleMedium),
                    const SizedBox(height: FinoraTokens.s12),
                    categoriesAsync.when(
                      data: (categories) {
                        // Siempre con el chip "+ Nueva" al final, incluso con
                        // la lista vacia: es la via para crear la primera.
                        return Wrap(
                          spacing: FinoraTokens.s8,
                          runSpacing: FinoraTokens.s8,
                          children: [
                            // GestureDetector externo: ChoiceChip no expone
                            // onLongPress, y el detector no interfiere con el
                            // tap del chip.
                            for (final c in categories)
                              GestureDetector(
                                onLongPress: () => _showCategoryMenu(c),
                                child: ChoiceChip(
                                  label: Text(c.name),
                                  avatar: Icon(
                                    categoryIcons[c.icon] ?? Icons.category,
                                    size: 18,
                                    color: _selectedCategoryId == c.id
                                        ? Colors.white
                                        : Color(c.color),
                                  ),
                                  selected: _selectedCategoryId == c.id,
                                  selectedColor: Color(c.color),
                                  backgroundColor: FinoraColors.surface,
                                  showCheckmark: false,
                                  pressElevation: 0,
                                  shape: StadiumBorder(
                                    side: BorderSide(
                                      color: _selectedCategoryId == c.id
                                          ? Color(c.color)
                                          : FinoraColors.border,
                                    ),
                                  ),
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _selectedCategoryId == c.id
                                        ? Colors.white
                                        : FinoraColors.textPrimary,
                                  ),
                                  onSelected: (_) => setState(
                                    () => _selectedCategoryId = c.id,
                                  ),
                                ),
                              ),
                            // Chip de accion para crear una categoria nueva
                            // del `kind` actual.
                            ActionChip(
                              label: const Text('Nueva'),
                              avatar: const Icon(
                                Icons.add,
                                size: 18,
                                color: FinoraColors.primary,
                              ),
                              backgroundColor: FinoraColors.surface,
                              shape: const StadiumBorder(
                                side: BorderSide(color: FinoraColors.primary),
                              ),
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: FinoraColors.primary,
                              ),
                              onPressed: _createCategory,
                            ),
                          ],
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('No se pudo cargar categorías: $e'),
                    ),
                    const SizedBox(height: FinoraTokens.s24),
                    Text('Cuenta', style: textTheme.titleMedium),
                    const SizedBox(height: FinoraTokens.s12),
                    if (noAccounts)
                      Container(
                        padding: const EdgeInsets.all(FinoraTokens.s12),
                        decoration: BoxDecoration(
                          color: FinoraColors.warning.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(
                            FinoraTokens.rInput,
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: FinoraColors.warning,
                            ),
                            SizedBox(width: FinoraTokens.s8),
                            Expanded(
                              child: Text(
                                'Crea una cuenta primero en Mis tarjetas',
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      // El selector conserva el dropdown pero decorado como card
                      // (radio 12, borde) con el icono del tipo de cuenta.
                      DropdownButtonFormField<String>(
                        initialValue: selectedAccountId,
                        decoration: InputDecoration(
                          prefixIcon: Icon(
                            _accountTypeIcon(selectedAccount?.type ?? 'cash'),
                            color: FinoraColors.textSecondary,
                          ),
                        ),
                        hint: const Text('Selecciona una cuenta'),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.name} (${_accountTypeLabel(a.type)})',
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedAccountId = v),
                      ),
                    const SizedBox(height: FinoraTokens.s24),
                    // Fecha y nota agrupadas en una sola card (radio 20). Se usa
                    // `Card` (un Material) para que las salpicaduras/ink de los
                    // ListTile se pinten correctamente sobre la superficie.
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.calendar_today_outlined),
                            title: const Text('Fecha'),
                            subtitle: Text(
                              DateFormat('d MMMM yyyy', 'es').format(_date),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _pickDate,
                          ),
                          const Divider(height: 1, color: FinoraColors.border),
                          ListTile(
                            leading: const Icon(Icons.notes_outlined),
                            title: const Text('Nota'),
                            subtitle: Text(
                              _noteCtrl.text.isEmpty
                                  ? 'Opcional'
                                  : _noteCtrl.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _editNote,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Boton "Guardar" fijo al fondo (pill alto 56), dentro del
              // SafeArea; con `resizeToAvoidBottomInset` (default) sube sobre el
              // teclado en lugar de quedar tapado.
              Padding(
                padding: const EdgeInsets.all(FinoraTokens.s16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: noAccounts ? null : _save,
                    style: ElevatedButton.styleFrom(
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Guardar'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialogo de nota con su propio `TextEditingController`, que vive y muere
/// con el dialogo. Antes el controller se creaba en `_editNote` y se
/// disponia inmediatamente despues del `await showDialog(...)`: el `pop`
/// resuelve el future ANTES de que termine la animacion de cierre, asi que
/// el `TextField` del dialogo (aun montado durante esa animacion) quedaba
/// escuchando un controller ya dispuesto y congelaba la app. Aqui el
/// controller se libera en `dispose()` del propio dialogo, que corre recien
/// cuando la ruta se desmonta del todo.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});
  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nota'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Agrega una nota (opcional)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
