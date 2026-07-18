import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/category_icons.dart';
import '../../../core/dates.dart';
import '../../../core/finora_colors.dart';
import '../../../core/money.dart';
import '../../../data/local/database.dart';

/// Fila reutilizable para mostrar una transaccion: icono circular con el
/// color de la categoria al 10% de opacidad, nombre + nota, fecha (en hora
/// de Lima) y monto alineado a la derecha (rojo/'-' gasto, verde/'+' ingreso).
///
/// [category] puede ser null (categoria borrada o aun no cargada en el mapa
/// de `categoriesMapProvider`): se degrada a un nombre generico y al icono
/// de fallback en vez de fallar.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, required this.category});
  final Txn txn;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final isExpense = txn.kind == 'expense';
    final amountColor = isExpense ? FinoraColors.expense : FinoraColors.income;
    // Sin categoria (borrada o aun no cargada): avatar gris neutro con el
    // icono generico, NUNCA el color del monto (fix T14). Con categoria: color
    // propio de la categoria sobre su mismo tono al 15%.
    final hasCategory = category != null;
    final iconColor =
        hasCategory ? Color(category!.color) : FinoraColors.textSecondary;
    final avatarBg = hasCategory
        ? iconColor.withValues(alpha: .15)
        : FinoraColors.border;
    final icon = categoryIcons[category?.icon] ?? Icons.category;
    final title = category?.name ?? 'Sin categoría';
    final note = txn.note;
    final dateLabel = DateFormat('d MMM', 'es').format(toLima(txn.occurredAt));
    final subtitle = (note != null && note.isNotEmpty) ? '$dateLabel · $note' : dateLabel;
    final sign = isExpense ? '-' : '+';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: avatarBg,
        child: Icon(icon, color: iconColor),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        '$sign${formatMoney(txn.amountCents.abs())}',
        style: TextStyle(color: amountColor, fontWeight: FontWeight.w700),
      ),
    );
  }
}
