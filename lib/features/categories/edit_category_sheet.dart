import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/category_icons.dart';
import '../../core/finora_colors.dart';
import '../../core/finora_snackbar.dart';
import '../../core/finora_tokens.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';

/// Colores predefinidos para el selector de color de categorias: la misma
/// paleta de dominio que las cuentas (`accountColorOptions` en
/// `edit_account_sheet.dart`) mas acentos extra para distinguir mas
/// categorias entre si.
const categoryColorOptions = <int>[
  0xFF16A34A, // primario
  0xFF22C55E, // ingreso
  0xFFEF4444, // gasto
  0xFFF59E0B, // alerta
  0xFF3B82F6, // ahorro
  0xFF8B5CF6, // inversión
  0xFF1E3A8A, // secundario
  0xFF0EA5E9, // celeste
  0xFFEC4899, // rosa
  0xFF14B8A6, // teal
  0xFF6366F1, // índigo
  0xFF78716C, // piedra
];

/// Bottom sheet de alta/edicion de una categoria: nombre, tipo (gasto/
/// ingreso, preseleccionado con [initialKind]), icono (de [categoryIcons]) y
/// color (de [categoryColorOptions]). Al guardar hace pop con el `id` de la
/// categoria creada/editada, para que el llamador pueda auto-seleccionarla
/// (ver `add_transaction_screen.dart`). Mismo patron de sheet que
/// `EditAccountSheet`.
///
/// Si [category] es no-nulo, el formulario se pre-llena y se reutiliza su
/// `id` (edicion). En edicion el tipo NO es editable: las transacciones ya
/// registradas conservan el `kind` original y cambiarlo dejaria a la
/// categoria inconsistente con sus movimientos.
class EditCategorySheet extends ConsumerStatefulWidget {
  const EditCategorySheet({
    super.key,
    this.initialKind = 'expense',
    this.category,
  });

  /// 'expense' | 'income'.
  final String initialKind;
  final Category? category;

  @override
  ConsumerState<EditCategorySheet> createState() => _EditCategorySheetState();
}

class _EditCategorySheetState extends ConsumerState<EditCategorySheet> {
  late final TextEditingController _nameCtrl;
  late String _kind;
  late String _icon;
  late int _color;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _kind = c?.kind ?? widget.initialKind;
    _icon = c?.icon ?? categoryIcons.keys.first;
    _color = c?.color ?? categoryColorOptions.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      FinoraSnackbar.error(context, 'Ingresa un nombre');
      return;
    }
    final isNew = widget.category == null;
    final id = widget.category?.id ?? const Uuid().v4();
    await ref
        .read(databaseProvider)
        .categoriesDao
        .upsert(
          CategoriesCompanion.insert(
            id: id,
            name: name,
            icon: _icon,
            color: _color,
            kind: _kind,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    if (mounted) {
      FinoraSnackbar.success(
          context, isNew ? 'Categoría creada' : 'Categoría actualizada');
      Navigator.of(context).pop(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: FinoraTokens.s16,
        right: FinoraTokens.s16,
        top: FinoraTokens.s16,
        bottom: MediaQuery.of(context).viewInsets.bottom + FinoraTokens.s16,
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
              widget.category == null ? 'Nueva categoría' : 'Editar categoría',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FinoraTokens.s16),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FinoraTokens.s16),
            // El tipo solo se elige al crear (ver doc de la clase).
            if (widget.category == null) ...[
              Text('Tipo', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: FinoraTokens.s8),
              Wrap(
                spacing: FinoraTokens.s8,
                children: [
                  ChoiceChip(
                    label: const Text('Gasto'),
                    selected: _kind == 'expense',
                    selectedColor: FinoraColors.expense,
                    labelStyle: TextStyle(
                      color: _kind == 'expense' ? Colors.white : null,
                    ),
                    onSelected: (_) => setState(() => _kind = 'expense'),
                  ),
                  ChoiceChip(
                    label: const Text('Ingreso'),
                    selected: _kind == 'income',
                    selectedColor: FinoraColors.income,
                    labelStyle: TextStyle(
                      color: _kind == 'income' ? Colors.white : null,
                    ),
                    onSelected: (_) => setState(() => _kind = 'income'),
                  ),
                ],
              ),
              const SizedBox(height: FinoraTokens.s16),
            ],
            Text('Icono', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: FinoraTokens.s8),
            Wrap(
              spacing: FinoraTokens.s8,
              runSpacing: FinoraTokens.s8,
              children: [
                for (final entry in categoryIcons.entries)
                  _IconOption(
                    icon: entry.value,
                    selected: _icon == entry.key,
                    color: Color(_color),
                    onTap: () => setState(() => _icon = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: FinoraTokens.s16),
            Text('Color', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: FinoraTokens.s8),
            Wrap(
              spacing: FinoraTokens.s12,
              runSpacing: FinoraTokens.s12,
              children: [
                for (final c in categoryColorOptions)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: _color == c
                            ? Border.all(
                                color: FinoraColors.textPrimary,
                                width: 3,
                              )
                            : null,
                      ),
                      child: _color == c
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: FinoraTokens.s24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
                child: const Text('Guardar'),
              ),
            ),
            const SizedBox(height: FinoraTokens.s8),
          ],
        ),
      ),
    );
  }
}

/// Una opcion del selector de iconos: squircle 44 con el icono; al estar
/// seleccionada se rellena con el color elegido (al 15%) y borde del color.
class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected
              ? Color.alphaBlend(
                  color.withValues(alpha: 0.15),
                  FinoraColors.surface,
                )
              : FinoraColors.surface,
          borderRadius: BorderRadius.circular(FinoraTokens.rInput),
          border: Border.all(
            color: selected ? color : FinoraColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Icon(
          icon,
          size: 22,
          color: selected ? color : FinoraColors.textSecondary,
        ),
      ),
    );
  }
}
