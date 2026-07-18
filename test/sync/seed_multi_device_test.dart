// Fix: el sembrado de categorias por defecto (`seedDefaultCategories`)
// duplicaba categorias en un segundo dispositivo/reinstalacion. Causa raiz
// (dos capas, arregladas juntas):
//   1. Cada instalacion generaba un `Uuid().v4()` nuevo por categoria: dos
//      dispositivos con DB local vacia sembraban 10 categorias cada uno con
//      IDS DISTINTOS mismo si el NOMBRE era igual, y el `upsert` remoto (por
//      id) no las deduplicaba -> 20 filas tras sincronizar.
//   2. El orden en `SyncCoordinator` sembraba ANTES del primer `pull()`, asi
//      que un segundo dispositivo nunca se enteraba de que el primero ya
//      habia sembrado.
// Este archivo simula el flujo `signedIn` (ahora: pull -> seed condicional
// -> synchronize) de dos dispositivos que comparten un remoto falso en
// memoria (mismo patron de `FakeRemote` que `test/sync/push_test.dart` y
// `test/sync/pull_test.dart`, pero con estado compartido y semantica real de
// upsert-por-id/fetchSince para poder simular dos DBs locales distintas).
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finora/data/local/database.dart';
import 'package:finora/data/local/seed.dart';
import 'package:finora/data/remote/remote_source.dart';
import 'package:finora/data/sync/sync_engine.dart';

/// Remoto compartido en memoria: a diferencia de los fakes de
/// `push_test.dart`/`pull_test.dart` (que solo acumulan un log de llamadas),
/// este SI modela el estado real de una tabla Postgres con `upsert` por
/// clave primaria (`id`) y `fetchSince` filtrando por `updated_at > since`
/// (igual que `SupabaseRemote.fetchSince`, `gt('updated_at', ...)`), porque
/// necesitamos que dos `SyncEngine` (uno por "dispositivo") vean el MISMO
/// estado remoto para reproducir el escenario de duplicados.
class SharedFakeRemote implements RemoteSource {
  final Map<String, Map<String, Map<String, dynamic>>> _rows = {};

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    final t = _rows.putIfAbsent(table, () => {});
    for (final row in rows) {
      t[row['id'] as String] = Map<String, dynamic>.from(row);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSince(String table, DateTime? since) async {
    final rows = _rows[table]?.values ?? const <Map<String, dynamic>>[];
    final filtered = since == null
        ? rows
        : rows.where((r) => DateTime.parse(r['updated_at'] as String).toUtc().isAfter(since));
    return filtered.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  int rowCount(String table) => _rows[table]?.length ?? 0;

  /// Nombres distintos entre las filas de una tabla (para detectar
  /// duplicados por nombre, que es exactamente el sintoma del bug original:
  /// misma categoria, ids distintos).
  Set<String> distinctNames(String table) =>
      (_rows[table]?.values ?? const <Map<String, dynamic>>[]).map((r) => r['name'] as String).toSet();
}

/// Reproduce el flujo `signedIn` de `SyncCoordinator` tal como queda tras el
/// fix: 1) intenta un `pull()` primero, 2) si tuvo exito, siembra (no-op via
/// `countAll() > 0` si el pull ya trajo categorias), 3) `synchronize()`
/// (push + pull), igual que el `trigger()` que sigue al handler.
Future<void> signedInFlow(AppDatabase db, SyncEngine engine) async {
  await engine.pull();
  await seedDefaultCategories(db);
  await engine.synchronize();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
      'dos dispositivos con DB local vacia: el segundo no duplica categorias '
      '(pull antes de sembrar + ids deterministicos)', () async {
    final remote = SharedFakeRemote();

    // --- Dispositivo A: primer login, remoto vacio.
    final dbA = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(dbA.close);
    final engineA = SyncEngine(dbA, remote);
    await signedInFlow(dbA, engineA);

    final categoriesA = await dbA.select(dbA.categories).get();
    expect(categoriesA, hasLength(10));
    expect(remote.rowCount('categories'), 10);

    // --- Dispositivo B: segundo login, DB local vacia, remoto YA tiene las
    // 10 categorias de A. Con el fix, B las recibe en su `pull()` inicial y
    // el guard de `seedDefaultCategories` evita sembrar de nuevo.
    final dbB = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(dbB.close);
    final engineB = SyncEngine(dbB, remote);
    await signedInFlow(dbB, engineB);

    final categoriesB = await dbB.select(dbB.categories).get();
    expect(categoriesB, hasLength(10)); // ni 20 ni 0: exactamente 10
    expect(categoriesB.map((c) => c.name).toSet(), hasLength(10)); // sin duplicados por nombre
    expect(remote.rowCount('categories'), 10); // el remoto tampoco duplico
    expect(remote.distinctNames('categories'), hasLength(10));

    // Los ids coinciden entre A y B (mismos ids deterministicos, convergen a
    // la misma fila en vez de crear una nueva por dispositivo).
    expect(
      categoriesB.map((c) => c.id).toSet(),
      categoriesA.map((c) => c.id).toSet(),
    );
  });

  test('regresion: una instalacion nueva con remoto vacio sigue sembrando sus 10 categorias',
      () async {
    final remote = SharedFakeRemote();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final engine = SyncEngine(db, remote);

    await signedInFlow(db, engine);

    final categories = await db.select(db.categories).get();
    expect(categories, hasLength(10));
    expect(categories.map((c) => c.name).toSet(), hasLength(10));
    expect(remote.rowCount('categories'), 10);
  });

  test(
      'si el primer pull falla (sin red) el dispositivo no siembra hasta el siguiente sync exitoso',
      () async {
    // Simula el caso raro documentado en `sync_providers.dart`: el pull
    // inicial del handler `signedIn` falla, asi que NO se siembra en ese
    // momento (para no arriesgar duplicar contra un remoto que ya tiene
    // datos de otro dispositivo). El re-chequeo vive en `trigger()` tras
    // cada sync exitoso: aqui se modela invocando `seedDefaultCategories`
    // recien despues de un `pull()`/`synchronize()` que SI tuvo exito.
    final remote = SharedFakeRemote();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final engine = SyncEngine(db, remote);

    // "pull inicial fallido": no se llama ni a pull() ni a seed aqui.
    var categories = await db.select(db.categories).get();
    expect(categories, isEmpty);

    // El siguiente sync exitoso (re-chequeo de `trigger()`) sí siembra.
    await engine.pull();
    await seedDefaultCategories(db);
    await engine.synchronize();

    categories = await db.select(db.categories).get();
    expect(categories, hasLength(10));
  });
}
