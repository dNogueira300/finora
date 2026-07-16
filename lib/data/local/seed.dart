import 'package:uuid/uuid.dart';
import 'database.dart';

const _uuid = Uuid();

Future<void> seedDefaultCategories(AppDatabase db) async {
  if (await db.categoriesDao.countAll() > 0) return;
  final now = DateTime.now().toUtc();
  const defaults = [
    ('Comida', 'restaurant', 0xFFEF4444, 'expense'),
    ('Pasajes', 'directions_bus', 0xFFF59E0B, 'expense'),
    ('Servicios', 'receipt_long', 0xFF3B82F6, 'expense'),
    ('Compras', 'shopping_bag', 0xFF8B5CF6, 'expense'),
    ('Salud', 'favorite', 0xFFEC4899, 'expense'),
    ('Educación', 'school', 0xFF14B8A6, 'expense'),
    ('Ocio', 'sports_esports', 0xFF6366F1, 'expense'),
    ('Pago de tarjeta', 'credit_score', 0xFF1E3A8A, 'income'),
    ('Sueldo', 'payments', 0xFF22C55E, 'income'),
    ('Otros ingresos', 'add_circle', 0xFF16A34A, 'income'),
  ];
  for (final (name, icon, color, kind) in defaults) {
    await db.categoriesDao.upsert(CategoriesCompanion.insert(
      id: _uuid.v4(),
      name: name,
      icon: icon,
      color: color,
      kind: kind,
      updatedAt: now,
    ));
  }
}
