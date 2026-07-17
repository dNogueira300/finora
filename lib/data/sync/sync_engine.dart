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
}
