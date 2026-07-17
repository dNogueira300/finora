import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/data/local/database.dart';
import 'package:finora/data/remote/remote_source.dart';
import 'package:finora/data/sync/sync_engine.dart';

class FakeRemote implements RemoteSource {
  final upserts = <String, List<Map<String, dynamic>>>{};
  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    upserts.putIfAbsent(table, () => []).addAll(rows);
  }
  @override
  Future<List<Map<String, dynamic>>> fetchSince(String t, DateTime? s) async => [];
}

void main() {
  test('push sube filas sucias y las marca limpias', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final remote = FakeRemote();
    await db.transactionsDao.insertTxn(TransactionsCompanion.insert(
        id: 't1', accountId: 'a1', categoryId: 'c1', kind: 'expense',
        amountCents: 500, occurredAt: DateTime(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 1)));
    final engine = SyncEngine(db, remote);
    await engine.push();
    expect(remote.upserts['transactions']!.single['id'], 't1');
    expect(remote.upserts['transactions']!.single.containsKey('is_dirty'), false);
    await engine.push(); // segunda pasada: nada sucio
    expect(remote.upserts['transactions']!.length, 1);
    await db.close();
  });
}
