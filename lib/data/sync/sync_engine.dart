import 'package:drift/drift.dart' show Value;
import '../local/database.dart';
import '../remote/remote_source.dart';
import 'table_specs.dart';

class SyncEngine {
  SyncEngine(this.db, this.remote) : specs = buildTableSpecs(db);
  final AppDatabase db;
  final RemoteSource remote;
  final List<SyncTableSpec> specs;

  Future<void> push() async {
    for (final spec in specs) {
      final rows = await spec.dirtyRows();
      if (rows.isEmpty) continue;
      await remote.upsert(spec.remoteName, rows);
      await spec.markClean(rows.map((r) => r['id'] as String).toList());
    }
  }

  Future<void> pull() async {
    for (final spec in specs) {
      final state = await (db.select(db.syncState)
            ..where((s) => s.entityTable.equals(spec.remoteName)))
          .getSingleOrNull();
      // Drift puede devolver DateTimes en zona local; normalizamos a UTC para
      // que las comparaciones con las marcas de tiempo remotas (siempre UTC)
      // sean consistentes y la marca de agua avance correctamente.
      final since = state?.lastPulledAt?.toUtc();
      final rows = await remote.fetchSince(spec.remoteName, since);
      DateTime? maxUpdated = since;
      for (final row in rows) {
        await spec.applyRemote(row);
        final u = DateTime.parse(row['updated_at'] as String).toUtc();
        if (maxUpdated == null || u.isAfter(maxUpdated)) maxUpdated = u;
      }
      if (maxUpdated != null) {
        await db.into(db.syncState).insertOnConflictUpdate(SyncStateCompanion(
          entityTable: Value(spec.remoteName),
          lastPulledAt: Value(maxUpdated),
        ));
      }
    }
  }

  Future<void> synchronize() async {
    await push();
    await pull();
  }
}
