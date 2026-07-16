import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'goals_dao.g.dart';

@DriftAccessor(tables: [SavingsGoals])
class GoalsDao extends DatabaseAccessor<AppDatabase> with _$GoalsDaoMixin {
  GoalsDao(super.db);
}
