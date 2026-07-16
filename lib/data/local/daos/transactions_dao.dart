import 'package:drift/drift.dart';
import '../../../core/dates.dart';
import '../database.dart';
import '../tables.dart';

part 'transactions_dao.g.dart';

@DriftAccessor(tables: [Transactions])
class TransactionsDao extends DatabaseAccessor<AppDatabase> with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  Expression<bool> _alive($TransactionsTable t) => t.deletedAt.isNull();

  Stream<List<Txn>> watchRecent(int limit) =>
      (select(transactions)
            ..where(_alive)
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
            ..limit(limit))
          .watch();

  /// [month] es un mes calendario en hora de Lima; la consulta usa limites UTC.
  Stream<List<Txn>> watchByMonth(DateTime month) {
    final (from, to) = monthRangeUtc(month);
    return (select(transactions)
          ..where((t) => _alive(t) &
              t.occurredAt.isBiggerOrEqualValue(from) &
              t.occurredAt.isSmallerThanValue(to))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .watch();
  }

  Future<void> insertTxn(TransactionsCompanion c) =>
      into(transactions).insertOnConflictUpdate(c.copyWith(
          isDirty: const Value(true),
          updatedAt: Value(DateTime.now().toUtc())));

  Future<void> softDelete(String id) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: Value(DateTime.now().toUtc()),
          updatedAt: Value(DateTime.now().toUtc()),
          isDirty: const Value(true),
        ),
      );

  Future<int> monthlyTotal({required String kind, required DateTime month}) async {
    final (from, to) = monthRangeUtc(month);
    final sum = transactions.amountCents.sum();
    final q = selectOnly(transactions)
      ..addColumns([sum])
      ..where(_alive(transactions) &
          transactions.kind.equals(kind) &
          transactions.occurredAt.isBiggerOrEqualValue(from) &
          transactions.occurredAt.isSmallerThanValue(to));
    return (await q.getSingle()).read(sum) ?? 0;
  }

  Future<Map<String, int>> totalsByCategory(DateTime month) async {
    final (from, to) = monthRangeUtc(month);
    final sum = transactions.amountCents.sum();
    final q = selectOnly(transactions)
      ..addColumns([transactions.categoryId, sum])
      ..where(_alive(transactions) &
          transactions.kind.equals('expense') &
          transactions.occurredAt.isBiggerOrEqualValue(from) &
          transactions.occurredAt.isSmallerThanValue(to))
      ..groupBy([transactions.categoryId]);
    final rows = await q.get();
    return {
      for (final r in rows) r.read(transactions.categoryId)!: r.read(sum) ?? 0,
    };
  }
}
