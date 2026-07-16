import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/data/local/database.dart';
import 'package:finora/data/local/seed.dart';
import 'package:finora/core/dates.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('seed inserta 10 categorias solo una vez', () async {
    await seedDefaultCategories(db);
    await seedDefaultCategories(db);
    expect(await db.categoriesDao.countAll(), 10);
  });

  test('balance = inicial + ingresos - gastos', () async {
    await db.accountsDao.upsert(AccountsCompanion.insert(
        id: 'a1', name: 'Efectivo', type: 'cash',
        initialBalanceCents: const Value(10000), updatedAt: DateTime.now().toUtc()));
    await db.transactionsDao.insertTxn(TransactionsCompanion.insert(
        id: 't1', accountId: 'a1', categoryId: 'c1', kind: 'expense',
        amountCents: 3000, occurredAt: DateTime.now(), updatedAt: DateTime.now().toUtc()));
    await db.transactionsDao.insertTxn(TransactionsCompanion.insert(
        id: 't2', accountId: 'a1', categoryId: 'c2', kind: 'income',
        amountCents: 5000, occurredAt: DateTime.now(), updatedAt: DateTime.now().toUtc()));
    expect(await db.accountsDao.balanceCents('a1'), 12000);
  });

  test('total mensual de gastos ignora borrados y otros meses', () async {
    final july = DateTime(2026, 7, 10);
    await db.transactionsDao.insertTxn(TransactionsCompanion.insert(
        id: 't1', accountId: 'a1', categoryId: 'c1', kind: 'expense',
        amountCents: 1000, occurredAt: limaToUtc(july), updatedAt: DateTime.now().toUtc()));
    await db.transactionsDao.insertTxn(TransactionsCompanion.insert(
        id: 't2', accountId: 'a1', categoryId: 'c1', kind: 'expense',
        amountCents: 999, occurredAt: limaToUtc(DateTime(2026, 6, 1)), updatedAt: DateTime.now().toUtc()));
    await db.transactionsDao.softDelete('t2');
    expect(await db.transactionsDao.monthlyTotal(kind: 'expense', month: july), 1000);
  });
}
