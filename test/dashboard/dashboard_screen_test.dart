import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/alerts/alerts_dao_ext.dart';
import 'package:finora/features/dashboard/dashboard_screen.dart';

// La mayoria de estos tests no pumpean AppShell ni el router:
// `DashboardScreen` usa `context.push`/`context.go` unicamente dentro de
// `onPressed`/`onTap` que la mayoria de estos tests nunca tocan, asi que no
// hace falta un GoRouter en el arbol. La excepcion es el test de navegacion
// del card "Metas de ahorro" (mas abajo), que si envuelve la pantalla en un
// `GoRouter` real, mismo patron que `add_transaction_screen_test.dart`.
void main() {
  // Cada test abre su propia base de datos en memoria (ver `setUp`), lo cual
  // hace que drift emita una advertencia benigna de "database class created
  // multiple times" al construir la segunda instancia en adelante.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUpAll(() async {
    // El locale pasado es ignorado por `intl`: esta llamada carga los datos
    // de TODOS los locales (incluido 'es', usado por `TxnTile`).
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Widget buildApp() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: DashboardScreen()),
    );
  }

  testWidgets('estado vacio: saludo, indicador de sync y S/ 0.00', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // Supabase.instance no esta inicializado en el entorno de test, asi que
    // currentUser es null y el saludo cae al fallback sin nombre.
    expect(find.text('Hola 👋'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done), findsOneWidget); // syncStatusProvider arranca en idle
    expect(find.text('Registra tu primer gasto con el botón +'), findsOneWidget);
    expect(find.text('S/ 0.00'), findsWidgets);

    // Desmontar el arbol y drenar los timers pendientes de drift (los
    // StreamProvider.autoDispose dejan un Timer de la conexion de drift que
    // solo se cancela una vez que el stream subscription se cierra tras el
    // dispose de los providers). Sin esto, flutter_test detecta "A Timer is
    // still pending even after the widget tree was disposed" en el tearDown.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tras insertar una transaccion, la tile aparece y los totales se actualizan',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // IMPORTANTE: NO envolver estas escrituras en `tester.runAsync()`. Se
    // probo esa variante (parece la solucion "obvia" para awaits directos en
    // la zona FakeAsync de testWidgets) y en este caso concreto provoca un
    // deadlock real de 10 minutos: `db` se crea en `setUp` (zona real, fuera
    // de FakeAsync) pero las suscripciones de los StreamProvider.autoDispose
    // de `DashboardScreen` se crean en `pumpWidget` (zona FakeAsync). Cuando
    // la escritura ocurre en la zona real de `runAsync`, `handleTableUpdates`
    // notifica de forma *sincronica* (StreamController(sync: true)) al
    // listener capturado en la zona FakeAsync, lo que crea una zona hija de
    // FakeAsync para la re-consulta cancelable (`runCancellable` en
    // `drift/src/runtime/cancellation_zone.dart`) justo en medio del await
    // real de `runAsync` — nada esta bombeando esa zona FakeAsync en ese
    // momento, y la escritura nunca completa (confirmado: timeout exacto de
    // 10 min, ver `drift` issue #1235 "Query does not complete if the
    // database is created outside WidgetTester.runAsync").
    //
    // La solucion real (tambien documentada por drift) es la inversa: NO
    // mezclar zonas. Como `db` ya se crea antes del `pumpWidget` (fuera de
    // FakeAsync) y aqui seguimos sin usar `runAsync`, todo el ciclo
    // escritura -> notificacion -> re-consulta -> rebuild ocurre en una
    // unica zona (FakeAsync), tal como ya hace lectura en el primer test
    // (que pasa sin problemas). Confirmado con un test de aislamiento
    // (`_debug_hang_test.dart`, ya eliminado) que este mismo patron sin
    // `runAsync` completa las 7 escrituras/pumps en ~2 s reales.
    await db.categoriesDao.upsert(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Comida',
      icon: 'restaurant',
      color: 0xFFEF4444,
      kind: 'expense',
      updatedAt: DateTime.now().toUtc(),
    ));
    await db.transactionsDao.insertTxn(TransactionsCompanion.insert(
      id: 't1',
      accountId: 'a1',
      categoryId: 'c1',
      kind: 'expense',
      amountCents: 4550,
      occurredAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Registra tu primer gasto con el botón +'), findsNothing);
    expect(find.text('Comida'), findsOneWidget); // TxnTile con el nombre de la categoria
    // La tile muestra "-S/ 45.50" (con signo, sin espacio); solo la tarjeta
    // "Gastos del mes" muestra exactamente "S/ 45.50", asi que sigue siendo
    // findsOneWidget.
    expect(find.text('S/ 45.50'), findsOneWidget); // "Gastos del mes" actualizado

    // Mismo drenado de timers pendientes que en el test anterior.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('sin metas, el card "Metas de ahorro" invita a crear la primera', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Metas de ahorro'), findsOneWidget);
    expect(find.text('Crea tu primera meta'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'el card "Metas de ahorro" muestra la meta con fecha limite mas proxima y navega a /goals al tocarlo',
      (tester) async {
    final now = DateTime.now().toUtc();
    // "Auto" vence antes que "Casa": debe ser la meta destacada aunque se
    // haya insertado despues (ver `nearestGoal` en `dashboard_screen.dart`).
    await db.goalsDao.upsert(SavingsGoalsCompanion.insert(
      id: 'g2',
      name: 'Casa',
      targetCents: 1000000,
      savedCents: const Value(100000),
      deadline: Value(now.add(const Duration(days: 365))),
      updatedAt: now,
    ));
    await db.goalsDao.upsert(SavingsGoalsCompanion.insert(
      id: 'g1',
      name: 'Auto',
      targetCents: 500000,
      savedCents: const Value(125000),
      deadline: Value(now.add(const Duration(days: 30))),
      updatedAt: now,
    ));

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
        GoRoute(path: '/goals', builder: (_, _) => const Scaffold(body: Text('pantalla metas'))),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Auto'), findsOneWidget); // meta destacada: vence primero
    expect(find.text('Casa'), findsNothing);
    expect(find.text('25%'), findsOneWidget); // 125000/500000

    await tester.tap(find.text('Metas de ahorro'));
    await tester.pumpAndSettle();

    expect(find.text('pantalla metas'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'la campana muestra un Badge "2" con alertas no leidas y desaparece tras marcar todas como leidas',
      (tester) async {
    await db.insertAlert('Límite de gasto alcanzado', 'Superaste tu límite mensual');
    await db.insertAlert('Vencimiento de pago', 'Tu tarjeta vence mañana');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await db.markAllRead();
    await tester.pumpAndSettle();

    // El Badge sigue en el arbol (envuelve la campana) pero sin label
    // visible: `isLabelVisible: unreadCount > 0` (ver `dashboard_screen.dart`).
    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
