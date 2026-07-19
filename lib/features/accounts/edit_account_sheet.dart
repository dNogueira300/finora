import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/finora_colors.dart';
import '../../core/finora_tokens.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import '../../services/notifications_service.dart';

/// Etiquetas en español de `Account.type`. Publico (sin `_`) para que
/// `cards_screen.dart` lo reutilice sin duplicar el mapa.
const accountTypeLabels = {
  'cash': 'Efectivo',
  'wallet': 'Billetera',
  'debit': 'Débito',
  'credit': 'Crédito',
};

String accountTypeLabel(String type) => accountTypeLabels[type] ?? type;

bool _isValidDay(int? day) => day != null && day >= 1 && day <= 31;

/// 8 colores predefinidos para el selector de color de cuentas/tarjetas:
/// incluye primario/secundario/ahorro/inversión/alerta/gasto de
/// `FinoraColors` mas un par de acentos adicionales para variedad.
const accountColorOptions = <int>[
  0xFF16A34A, // primario
  0xFF1E3A8A, // secundario
  0xFF3B82F6, // ahorro
  0xFF8B5CF6, // inversión
  0xFFF59E0B, // alerta
  0xFFEF4444, // gasto
  0xFF0EA5E9, // celeste
  0xFFEC4899, // rosa
];

/// Bottom sheet de alta/edicion de una cuenta (Task 16). Referencia Stitch
/// "Mis Tarjetas Premium": nombre, tipo, saldo inicial (cash/wallet/debit) o
/// linea de credito + dia de cierre + dia de pago (credit), ultimos 4
/// digitos (debit/credit) y selector de color entre 8 predefinidos.
///
/// Si `account` es no-nulo, el formulario se pre-llena y `_save` reutiliza
/// el mismo `id` (edicion); si es nulo, se genera un `Uuid().v4()` nuevo
/// (alta).
class EditAccountSheet extends ConsumerStatefulWidget {
  const EditAccountSheet({super.key, this.account});
  final Account? account;

  @override
  ConsumerState<EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends ConsumerState<EditAccountSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _statementDayCtrl;
  late final TextEditingController _paymentDueDayCtrl;
  late final TextEditingController _last4Ctrl;
  late String _type;
  late int _color;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _nameCtrl = TextEditingController(text: a?.name ?? '');
    _type = a?.type ?? 'cash';
    _color = a?.color ?? accountColorOptions.first;
    final prefillCents =
        a == null ? null : (a.type == 'credit' ? a.creditLimitCents : a.initialBalanceCents);
    _amountCtrl = TextEditingController(
        text: prefillCents == null ? '' : (prefillCents / 100).toStringAsFixed(2));
    _statementDayCtrl = TextEditingController(text: a?.statementDay?.toString() ?? '');
    _paymentDueDayCtrl = TextEditingController(text: a?.paymentDueDay?.toString() ?? '');
    _last4Ctrl = TextEditingController(text: a?.last4 ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _statementDayCtrl.dispose();
    _paymentDueDayCtrl.dispose();
    _last4Ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ingresa un nombre')));
      return;
    }

    final isCredit = _type == 'credit';
    final amountCents = parseMoney(_amountCtrl.text) ?? 0;
    int? statementDay;
    int? paymentDueDay;

    if (isCredit) {
      if (amountCents <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ingresa una línea de crédito válida')));
        return;
      }
      statementDay = int.tryParse(_statementDayCtrl.text);
      paymentDueDay = int.tryParse(_paymentDueDayCtrl.text);
      if (!_isValidDay(statementDay) || !_isValidDay(paymentDueDay)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ingresa día de cierre y día de pago válidos (1-31)')));
        return;
      }
    }

    final last4Raw = _last4Ctrl.text.trim();
    if (last4Raw.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(last4Raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Los últimos 4 dígitos deben ser 4 números')));
      return;
    }

    final id = widget.account?.id ?? const Uuid().v4();
    await ref.read(databaseProvider).accountsDao.upsert(AccountsCompanion.insert(
          id: id,
          name: name,
          type: _type,
          initialBalanceCents: Value(isCredit ? 0 : amountCents),
          creditLimitCents: Value(isCredit ? amountCents : null),
          statementDay: Value(isCredit ? statementDay : null),
          paymentDueDay: Value(isCredit ? paymentDueDay : null),
          last4: Value(last4Raw.isEmpty ? null : last4Raw),
          color: Value(_color),
          updatedAt: DateTime.now().toUtc(),
        ));
    // Reprograma recordatorios de pago (Task 22) tras guardar CUALQUIER
    // cuenta, no solo las de credito: si una tarjeta se convierte a otro
    // tipo, `rescheduleCardRemindersFromDb` cancela su recordatorio
    // pendiente igual (cancela todo antes de reagendar). Best-effort (su
    // propio try/catch): un fallo no debe impedir guardar la cuenta.
    await rescheduleCardRemindersFromDb(
        ref.read(databaseProvider), ref.read(notificationsServiceProvider));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isCredit = _type == 'credit';
    final isDebit = _type == 'debit';
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
              widget.account == null ? 'Nueva cuenta' : 'Editar cuenta',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text('Tipo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in accountTypeLabels.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _type == entry.key,
                    selectedColor: FinoraColors.primary,
                    labelStyle: TextStyle(color: _type == entry.key ? Colors.white : null),
                    onSelected: (_) => setState(() => _type = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (isCredit) ...[
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Línea de crédito',
                  prefixText: 'S/ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _statementDayCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 2,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'Día de cierre',
                          counterText: '',
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _paymentDueDayCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 2,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'Día de pago',
                          counterText: '',
                          border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _last4Ctrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                    labelText: 'Últimos 4 dígitos', border: OutlineInputBorder()),
              ),
            ] else ...[
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Saldo inicial',
                  prefixText: 'S/ ',
                  border: OutlineInputBorder(),
                ),
              ),
              if (isDebit) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _last4Ctrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                      labelText: 'Últimos 4 dígitos', border: OutlineInputBorder()),
                ),
              ],
            ],
            const SizedBox(height: 8),
            Text('Color', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in accountColorOptions)
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
                style: ElevatedButton.styleFrom(
                  shape: const StadiumBorder(),
                ),
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
