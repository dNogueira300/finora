import 'package:drift/drift.dart';
import '../database.dart';
import '../tables.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<AppDatabase> with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  Stream<List<Category>> watchByKind(String kind) => (select(categories)
        ..where((c) => c.deletedAt.isNull() & c.kind.equals(kind))
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .watch();

  Future<void> upsert(CategoriesCompanion c) =>
      into(categories).insertOnConflictUpdate(c.copyWith(isDirty: const Value(true)));

  Future<int> countAll() async {
    final count = categories.id.count();
    final q = selectOnly(categories)..addColumns([count]);
    return (await q.getSingle()).read(count) ?? 0;
  }
}
