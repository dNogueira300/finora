import 'package:drift/drift.dart';
import '../database.dart';
import '../tables.dart';

part 'accounts_dao.g.dart';

@DriftAccessor(tables: [Accounts, Transactions])
class AccountsDao extends DatabaseAccessor<AppDatabase> with _$AccountsDaoMixin {
  AccountsDao(super.db);

  Stream<List<Account>> watchActive() => (select(accounts)
        ..where((a) => a.deletedAt.isNull() & a.isArchived.equals(false))
        ..orderBy([(a) => OrderingTerm.asc(a.name)]))
      .watch();

  Future<void> upsert(AccountsCompanion c) =>
      into(accounts).insertOnConflictUpdate(c.copyWith(
          isDirty: const Value(true),
          updatedAt: Value(DateTime.now().toUtc())));

  Future<void> softDelete(String id) =>
      (update(accounts)..where((a) => a.id.equals(id))).write(AccountsCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        updatedAt: Value(DateTime.now().toUtc()),
        isDirty: const Value(true),
      ));

  /// cash/wallet/debit: inicial + ingresos - gastos.
  /// credit: usado = gastos - ingresos(pagos).
  Future<int> balanceCents(String accountId) async {
    final acc = await (select(accounts)..where((a) => a.id.equals(accountId))).getSingle();
    final sum = transactions.amountCents.sum();
    Future<int> totalOf(String kind) async {
      final q = selectOnly(transactions)
        ..addColumns([sum])
        ..where(transactions.deletedAt.isNull() &
            transactions.accountId.equals(accountId) &
            transactions.kind.equals(kind));
      return (await q.getSingle()).read(sum) ?? 0;
    }
    final expenses = await totalOf('expense');
    final incomes = await totalOf('income');
    if (acc.type == 'credit') return expenses - incomes;
    return acc.initialBalanceCents + incomes - expenses;
  }
}
