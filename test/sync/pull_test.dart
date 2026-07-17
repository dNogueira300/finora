import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/data/local/database.dart';
import 'package:finora/data/remote/remote_source.dart';
import 'package:finora/data/sync/sync_engine.dart';

class FakeRemote implements RemoteSource {
  Map<String, List<Map<String, dynamic>>> data = {};
  DateTime? lastSince;
  @override
  Future<void> upsert(String t, List<Map<String, dynamic>> rows) async {}
  @override
  Future<List<Map<String, dynamic>>> fetchSince(String t, DateTime? since) async {
    lastSince = since;
    return data[t] ?? [];
  }
}

Map<String, dynamic> _remoteTxn(String id, DateTime updated, {int cents = 100}) => {
  'id': id, 'account_id': 'a1', 'category_id': 'c1', 'kind': 'expense',
  'amount_cents': cents, 'note': null,
  'occurred_at': updated.toIso8601String(),
  'updated_at': updated.toIso8601String(), 'deleted_at': null,
};

void main() {
  late AppDatabase db;
  late FakeRemote remote;
  late SyncEngine engine;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = FakeRemote();
    engine = SyncEngine(db, remote);
  });
  tearDown(() => db.close());

  test('pull inserta filas remotas y avanza last_pulled_at', () async {
    final t = DateTime.utc(2026, 7, 10, 12);
    remote.data['transactions'] = [_remoteTxn('t1', t)];
    await engine.pull();
    final local = await db.select(db.transactions).get();
    expect(local.single.id, 't1');
    expect(local.single.isDirty, false);
    final state = await db.select(db.syncState).get();
    expect(state.any((s) => s.entityTable == 'transactions' && s.lastPulledAt != null), true);
  });

  test('LWW: una fila local sucia mas nueva no se sobreescribe', () async {
    final oldRemote = DateTime.utc(2026, 7, 1);
    final newerLocal = DateTime.utc(2026, 7, 5);
    await db.transactionsDao.insertTxn(TransactionsCompanion.insert(
        id: 't1', accountId: 'a1', categoryId: 'c1', kind: 'expense',
        amountCents: 999, occurredAt: DateTime(2026, 7, 1), updatedAt: newerLocal));
    remote.data['transactions'] = [_remoteTxn('t1', oldRemote, cents: 100)];
    await engine.pull();
    final row = await db.select(db.transactions).get();
    expect(row.single.amountCents, 999); // gano lo local
  });

  test('pull no-op no reescribe la marca de agua', () async {
    final t = DateTime.utc(2026, 7, 10, 12);
    remote.data['transactions'] = [_remoteTxn('t1', t)];
    await engine.pull();
    final before = await (db.select(db.syncState)).get();

    // Segunda pasada: el remoto ya no devuelve filas nuevas (simula que no
    // hay nada que sincronizar). No deberia reescribirse syncState.
    remote.data['transactions'] = [];

    // Verificacion fuerte: no debe haber ningun evento de tableUpdates sobre
    // syncState durante la segunda pasada (eso es justo lo que rearmaria el
    // debounce del SyncCoordinator y causaria el bucle no-op).
    final events = <void>[];
    final sub = db
        .tableUpdates(TableUpdateQuery.onTable(db.syncState))
        .listen(events.add);
    await engine.pull();
    // Le damos tiempo al stream de drift (asincrono) a entregar cualquier
    // evento pendiente antes de afirmar que no hubo ninguno.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(events, isEmpty);

    final after = await (db.select(db.syncState)).get();
    expect(
      after.map((s) => (s.entityTable, s.lastPulledAt)).toList(),
      before.map((s) => (s.entityTable, s.lastPulledAt)).toList(),
    );
  });
}
