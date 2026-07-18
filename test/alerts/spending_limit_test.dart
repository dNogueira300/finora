// Task 23: alerta de limite de consumo mensual.
//
// El "Step 3: Prueba manual" del brief (limite S/100, gasto de S/95 ->
// notificacion 90%, gasto adicional de S/10 -> "superaste", un tercer gasto
// -> no repite) se automatiza aqui como pruebas de integracion de
// `checkSpendingLimit` con una base de datos en memoria real y un
// `FakeNotificationsPlugin` (mismo seam/patron que
// `test/services/notifications_service_test.dart`, para no tocar platform
// channels). La verificacion en dispositivo real de la notificacion mostrada
// por Android queda pendiente (no se puede automatizar sin un
// emulador/dispositivo).
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/alerts/spending_limit_watcher.dart';
import 'package:finora/features/settings/settings_screen.dart' show currentUserIdProvider;
import 'package:finora/features/transactions/add_transaction_screen.dart';
import 'package:finora/services/notifications_service.dart';

/// Copia local minima del fake de `test/services/notifications_service_test.dart`:
/// registra las notificaciones "mostradas" sin tocar platform channels.
class FakeNotificationsPlugin implements NotificationsPlugin {
  final List<({int id, String title, String body})> shown = [];

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {}

  @override
  Future<void> requestAndroidPermission() async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    shown.add((id: id, title: title, body: body));
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String payload,
  }) async {}
}

void main() {
  test('evalua el limite mensual', () {
    expect(evaluateLimit(50000, 100000), LimitStatus.ok);
    expect(evaluateLimit(90000, 100000), LimitStatus.near);
    expect(evaluateLimit(100001, 100000), LimitStatus.exceeded);
  });

  group('checkSpendingLimit', () {
    // Cada test abre su propia base de datos en memoria (ver `setUp`), lo
    // cual hace que drift emita una advertencia benigna de "database class
    // created multiple times".
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    late AppDatabase db;
    late FakeNotificationsPlugin plugin;
    late NotificationsService service;
    const userId = 'u1';

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      plugin = FakeNotificationsPlugin();
      service = NotificationsService(plugin, db);
    });

    tearDown(() => db.close());

    Future<void> addExpense(String id, int amountCents) =>
        db.transactionsDao.insertTxn(TransactionsCompanion.insert(
          id: id,
          accountId: 'a1',
          categoryId: 'c1',
          kind: 'expense',
          amountCents: amountCents,
          occurredAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ));

    Future<void> setLimit(int limitCents) => db.settingsDao.upsert(UserSettingsCompanion.insert(
        id: userId, monthlyLimitCents: Value(limitCents), updatedAt: DateTime.now().toUtc()));

    test(
        'limite S/100: gasto a S/95 notifica 90%; gasto adicional a S/105 notifica "superado"; '
        'un tercer gasto no repite ninguna', () async {
      await setLimit(10000);

      await addExpense('t1', 9500);
      await checkSpendingLimit(db, service, userId);
      expect(plugin.shown, hasLength(1));
      expect(plugin.shown.single.title, 'Límite de gasto: 90%');
      expect(plugin.shown.single.body, 'Vas en S/ 95.00 de tu límite de S/ 100.00 este mes (90%)');

      await addExpense('t2', 1000); // total 10500 > 10000
      await checkSpendingLimit(db, service, userId);
      expect(plugin.shown, hasLength(2));
      expect(plugin.shown[1].title, 'Límite de gasto superado');
      expect(plugin.shown[1].body, 'Superaste tu límite mensual de S/ 100.00');

      await addExpense('t3', 500); // total 11000, sigue excedido
      await checkSpendingLimit(db, service, userId);
      expect(plugin.shown, hasLength(2)); // sin nueva notificacion (ambos umbrales ya avisados)

      final alerts = await db.select(db.localAlerts).get();
      expect(alerts, hasLength(2)); // showNow inserta 1 alerta cada vez que notifica: sin duplicados
    });

    test('sin monthly_limit_cents configurado: no notifica nada', () async {
      await addExpense('t1', 999999);
      await checkSpendingLimit(db, service, userId);
      expect(plugin.shown, isEmpty);
      expect(await db.select(db.localAlerts).get(), isEmpty);
    });

    test('gasto exactamente al 90% del limite: near', () async {
      await setLimit(10000);
      await addExpense('t1', 9000); // exactamente 90%
      await checkSpendingLimit(db, service, userId);
      expect(plugin.shown, hasLength(1));
      expect(plugin.shown.single.title, 'Límite de gasto: 90%');
    });

    test('gasto exactamente igual al limite (100%): sigue siendo near, no exceeded', () async {
      await setLimit(10000);
      await addExpense('t1', 10000); // spent == limit
      await checkSpendingLimit(db, service, userId);
      expect(plugin.shown, hasLength(1));
      expect(plugin.shown.single.title, 'Límite de gasto: 90%');
    });
  });

  group('AddTransactionScreen dispara checkSpendingLimit al guardar un gasto', () {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    late AppDatabase db;
    late FakeNotificationsPlugin plugin;
    const userId = 'u1';

    setUpAll(() async {
      await initializeDateFormatting();
    });

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      plugin = FakeNotificationsPlugin();
    });

    tearDown(() => db.close());

    Future<void> growTestSurface(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> drainTimers(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('guardar un gasto que supera el limite inserta la alerta "Límite de gasto superado"',
        (tester) async {
      await growTestSurface(tester);
      await db.categoriesDao.upsert(CategoriesCompanion.insert(
        id: 'c1',
        name: 'Comida',
        icon: 'restaurant',
        color: 0xFFEF4444,
        kind: 'expense',
        updatedAt: DateTime.now().toUtc(),
      ));
      await db.accountsDao.upsert(AccountsCompanion.insert(
        id: 'a1',
        name: 'Cuenta principal',
        type: 'cash',
        updatedAt: DateTime.now().toUtc(),
      ));
      await db.settingsDao.upsert(UserSettingsCompanion.insert(
          id: userId, monthlyLimitCents: const Value(1000), updatedAt: DateTime.now().toUtc()));

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
          GoRoute(path: '/add', builder: (_, _) => const AddTransactionScreen()),
        ],
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserIdProvider.overrideWithValue(userId),
          notificationsServiceProvider.overrideWithValue(NotificationsService(plugin, db)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('es')],
        ),
      ));
      await tester.pumpAndSettle();

      router.push('/add');
      await tester.pumpAndSettle();

      // Monto S/ 15.00 > limite S/ 10.00 configurado arriba.
      await tester.enterText(find.byType(TextField).first, '15.00');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Comida'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuenta principal (Efectivo)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget); // el pop no se bloqueo

      final alerts = await db.select(db.localAlerts).get();
      expect(alerts, hasLength(1));
      expect(alerts.single.title, 'Límite de gasto superado');

      await drainTimers(tester);
    });
  });
}
