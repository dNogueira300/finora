import 'package:flutter/material.dart';

/// Mapea el nombre de icono guardado en `Categories.icon` (nombre de icono
/// Material, ej. 'restaurant') al `IconData` correspondiente. Se centraliza
/// aca porque `TxnTile` (Task 14) y los formularios/listados de categorias
/// (Tasks 15/18) lo necesitan por igual.
///
/// Cubre los 10 nombres de icono sembrados por `seedDefaultCategories`
/// (ver `lib/data/local/seed.dart`). Para un nombre desconocido, usar el
/// fallback: `categoryIcons[name] ?? Icons.category`.
const Map<String, IconData> categoryIcons = {
  'restaurant': Icons.restaurant,
  'directions_bus': Icons.directions_bus,
  'receipt_long': Icons.receipt_long,
  'shopping_bag': Icons.shopping_bag,
  'favorite': Icons.favorite,
  'school': Icons.school,
  'sports_esports': Icons.sports_esports,
  'credit_score': Icons.credit_score,
  'payments': Icons.payments,
  'add_circle': Icons.add_circle,
};
