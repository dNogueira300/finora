import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// Extension sobre `AppDatabase` para el centro de alertas locales (Task 20).
/// `LocalAlerts` (Task 4) es una tabla local-only: no se sincroniza con
/// Supabase y no tiene columnas de soft-delete, asi que aqui el borrado es
/// fisico (`delete`), a diferencia del resto de DAOs de la app. Las tareas
/// 22-23 llamaran `insertAlert` cada vez que generen una notificacion del
/// sistema, dejando historial navegable en `AlertsScreen`.
extension AlertsDaoExt on AppDatabase {
  /// Inserta una alerta nueva: `id` es un UUID v4, `createdAt` se guarda en
  /// UTC (`DateTime.now().toUtc()`) e `isRead` arranca en `false`.
  Future<void> insertAlert(String title, String body) {
    return into(localAlerts).insert(LocalAlertsCompanion.insert(
      id: const Uuid().v4(),
      title: title,
      body: body,
      createdAt: DateTime.now().toUtc(),
    ));
  }

  /// Todas las alertas, ordenadas de mas reciente a mas antigua.
  Stream<List<LocalAlert>> watchAlerts() => (select(localAlerts)
        ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
      .watch();

  /// Marca todas las alertas como leidas.
  Future<void> markAllRead() =>
      update(localAlerts).write(const LocalAlertsCompanion(isRead: Value(true)));

  /// Cantidad de alertas no leidas, en vivo.
  Stream<int> unreadCount() {
    final count = localAlerts.id.count();
    final query = selectOnly(localAlerts)
      ..addColumns([count])
      ..where(localAlerts.isRead.equals(false));
    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  /// Borra fisicamente una alerta (swipe-to-dismiss en `AlertsScreen`).
  Future<void> deleteAlert(String id) =>
      (delete(localAlerts)..where((a) => a.id.equals(id))).go();
}
