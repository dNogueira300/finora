import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';
import 'daos/transactions_dao.dart';
import 'daos/accounts_dao.dart';
import 'daos/categories_dao.dart';
import 'daos/goals_dao.dart';
import 'daos/settings_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Accounts, Categories, Transactions, SavingsGoals, UserSettings, SyncState, LocalAlerts],
  daos: [TransactionsDao, AccountsDao, CategoriesDao, GoalsDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'finora'));
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;
}
