import 'package:drift/drift.dart';
import '../database.dart';
import '../tables.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [UserSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<UserSetting?> get(String userId) =>
      (select(userSettings)..where((s) => s.id.equals(userId))).getSingleOrNull();

  Future<void> upsert(UserSettingsCompanion c) =>
      into(userSettings).insertOnConflictUpdate(c.copyWith(
          isDirty: const Value(true),
          updatedAt: Value(DateTime.now().toUtc())));
}
