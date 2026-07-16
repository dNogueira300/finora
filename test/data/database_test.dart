import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/data/local/database.dart';

void main() {
  test('la base abre y las tablas existen', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.syncState).insert(
        SyncStateCompanion.insert(entityTable: 'transactions'));
    final rows = await db.select(db.syncState).get();
    expect(rows.single.entityTable, 'transactions');
    await db.close();
  });
}
