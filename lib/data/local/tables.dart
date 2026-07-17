import 'package:drift/drift.dart';

mixin SyncColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();
}

@DataClassName('Account')
class Accounts extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get type => text()(); // cash | wallet | debit | credit
  IntColumn get initialBalanceCents => integer().withDefault(const Constant(0))();
  IntColumn get creditLimitCents => integer().nullable()();
  IntColumn get statementDay => integer().nullable()(); // dia de cierre 1-31
  IntColumn get paymentDueDay => integer().nullable()(); // dia de pago 1-31
  TextColumn get last4 => text().nullable()();
  IntColumn get color => integer().withDefault(const Constant(0xFF16A34A))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Category')
class Categories extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get icon => text()(); // nombre de icono Material, ej. 'restaurant'
  IntColumn get color => integer()();
  TextColumn get kind => text()(); // expense | income
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Txn')
class Transactions extends Table with SyncColumns {
  TextColumn get accountId => text()();
  TextColumn get categoryId => text()();
  TextColumn get kind => text()(); // expense | income
  IntColumn get amountCents => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SavingsGoal')
class SavingsGoals extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get targetCents => integer()();
  IntColumn get savedCents => integer().withDefault(const Constant(0))();
  DateTimeColumn get deadline => dateTime().nullable()();
  IntColumn get color => integer().withDefault(const Constant(0xFF3B82F6))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('UserSetting')
class UserSettings extends Table with SyncColumns {
  // id = user_id de Supabase
  IntColumn get monthlyLimitCents => integer().nullable()();
  IntColumn get alertDaysBeforeDue => integer().withDefault(const Constant(3))();
  // Solo local: no existe en remoto, excluir del JSON de push (Task 11).
  BoolColumn get biometricEnabled => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncStateRow')
class SyncState extends Table {
  // Nota: no se puede llamar `tableName` (colisiona con Table.tableName del DSL de drift).
  TextColumn get entityTable => text()();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {entityTable};
}

@DataClassName('LocalAlert')
class LocalAlerts extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}
