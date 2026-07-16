import 'package:drift/drift.dart';
import '../database.dart';
import '../tables.dart';

part 'goals_dao.g.dart';

@DriftAccessor(tables: [SavingsGoals])
class GoalsDao extends DatabaseAccessor<AppDatabase> with _$GoalsDaoMixin {
  GoalsDao(super.db);

  Stream<List<SavingsGoal>> watchAll() => (select(savingsGoals)
        ..where((g) => g.deletedAt.isNull())
        ..orderBy([(g) => OrderingTerm.asc(g.deadline)]))
      .watch();

  Future<void> upsert(SavingsGoalsCompanion c) =>
      into(savingsGoals).insertOnConflictUpdate(c.copyWith(
          isDirty: const Value(true),
          updatedAt: Value(DateTime.now().toUtc())));

  Future<void> softDelete(String id) =>
      (update(savingsGoals)..where((g) => g.id.equals(id))).write(SavingsGoalsCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        updatedAt: Value(DateTime.now().toUtc()),
        isDirty: const Value(true),
      ));
}
