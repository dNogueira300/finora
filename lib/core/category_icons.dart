import 'package:flutter/material.dart';

/// Mapea el nombre de icono guardado en `Categories.icon` (nombre de icono
/// Material, ej. 'restaurant') al `IconData` correspondiente. Se centraliza
/// aca porque `TxnTile` (Task 14) y los formularios/listados de categorias
/// (Tasks 15/18) lo necesitan por igual.
///
/// Los primeros 10 nombres son los sembrados por `seedDefaultCategories`
/// (ver `lib/data/local/seed.dart`); el resto son opciones adicionales para
/// las categorias creadas por el usuario (`EditCategorySheet`). Para un
/// nombre desconocido, usar el fallback: `categoryIcons[name] ?? Icons.category`.
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
  // Opciones adicionales para categorias personalizadas.
  'home': Icons.home,
  'directions_car': Icons.directions_car,
  'local_gas_station': Icons.local_gas_station,
  'flight': Icons.flight,
  'coffee': Icons.coffee,
  'local_grocery_store': Icons.local_grocery_store,
  'fitness_center': Icons.fitness_center,
  'pets': Icons.pets,
  'child_care': Icons.child_care,
  'phone_iphone': Icons.phone_iphone,
  'wifi': Icons.wifi,
  'movie': Icons.movie,
  'music_note': Icons.music_note,
  'card_giftcard': Icons.card_giftcard,
  'checkroom': Icons.checkroom,
  'content_cut': Icons.content_cut,
  'build': Icons.build,
  'work': Icons.work,
  'savings': Icons.savings,
  'trending_up': Icons.trending_up,
  'attach_money': Icons.attach_money,
  'medical_services': Icons.medical_services,
  'sports_soccer': Icons.sports_soccer,
  'menu_book': Icons.menu_book,
};
