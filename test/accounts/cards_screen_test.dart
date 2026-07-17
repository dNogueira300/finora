import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:finora/core/finora_colors.dart';
import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/accounts/cards_screen.dart';

void main() {
  // Cada test abre su propia base de datos en memoria (ver `setUp`), lo cual
  // hace que drift emita una advertencia benigna de "database class created
  // multiple times" al construir la segunda instancia en adelante.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  // El carrusel de tarjetas + la lista de billeteras no entran en el tamaño
  // de superficie por defecto de los tests (800x600): se agranda para que el
  // FAB "Nueva cuenta" y todo el contenido queden visibles sin necesidad de
  // scroll manual (mismo patron que `add_transaction_screen_test.dart`).
  Future<void> growTestSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> drainTimers(WidgetTester tester) async {
    // Desmontar el arbol y drenar los timers pendientes de drift (los
    // StreamProvider.autoDispose dejan un Timer de la conexion de drift que
    // solo se cancela una vez que el stream subscription se cierra tras el
    // dispose de los providers).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Widget buildApp() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es')],
        home: const CardsScreen(),
      ),
    );
  }

  testWidgets('crear una cuenta de efectivo desde el FAB la muestra en la lista',
      (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(
      find.text('Aún no tienes cuentas.\nToca "Nueva cuenta" para crear la primera.'),
      findsOneWidget,
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // El campo "Nombre" es el primer TextField del formulario (tipo cash ya
    // viene seleccionado por defecto).
    await tester.enterText(find.byType(TextField).first, 'Efectivo diario');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Efectivo diario'), findsOneWidget);
    expect(find.text('Efectivo'), findsOneWidget); // subtitulo del tipo
    expect(find.text('S/ 0.00'), findsOneWidget); // saldo inicial por defecto

    final rows = await db.select(db.accounts).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Efectivo diario');
    expect(rows.single.type, 'cash');

    await drainTimers(tester);
  });

  testWidgets('editar una cuenta existente pre-llena el formulario y mantiene el mismo id',
      (tester) async {
    await growTestSurface(tester);
    await db.accountsDao.upsert(AccountsCompanion.insert(
      id: 'a1',
      name: 'Cuenta vieja',
      type: 'wallet',
      initialBalanceCents: const Value(5000),
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Cuenta vieja'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Editar'));
    await tester.pumpAndSettle();

    // El formulario de edicion pre-llena nombre y saldo inicial.
    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller?.text, 'Cuenta vieja');
    expect(find.text('50.00'), findsOneWidget); // saldo inicial precargado

    await tester.enterText(find.byType(TextField).first, 'Cuenta nueva');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Cuenta nueva'), findsOneWidget);
    expect(find.text('Cuenta vieja'), findsNothing);

    final rows = await db.select(db.accounts).get();
    expect(rows, hasLength(1)); // se actualizo la fila existente, no se creo una nueva
    expect(rows.single.id, 'a1');
    expect(rows.single.name, 'Cuenta nueva');

    await drainTimers(tester);
  });

  testWidgets(
      'la barra de uso de una tarjeta de credito crece con gastos y baja con el pago',
      (tester) async {
    await growTestSurface(tester);
    await db.accountsDao.upsert(AccountsCompanion.insert(
      id: 'cc1',
      name: 'Visa Oro',
      type: 'credit',
      creditLimitCents: const Value(100000), // S/ 1,000.00
      statementDay: const Value(5),
      paymentDueDay: const Value(15),
      last4: const Value('4242'),
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Disponible: S/ 1,000.00'), findsOneWidget);

    // Gasto del 95% de la linea: la barra debe crecer y ponerse roja
    // (umbral > 90%).
    await db.transactionsDao.insertTxn(TransactionsCompanion.insert(
      id: 't1',
      accountId: 'cc1',
      categoryId: 'c1',
      kind: 'expense',
      amountCents: 95000,
      occurredAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Disponible: S/ 50.00'), findsOneWidget);
    var bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.95, 0.001));
    expect((bar.valueColor as AlwaysStoppedAnimation<Color?>).value, FinoraColors.expense);

    // "Pago de tarjeta" (income) reduce lo usado: 95000 - 45000 = 50000 (50%).
    await db.transactionsDao.insertTxn(TransactionsCompanion.insert(
      id: 't2',
      accountId: 'cc1',
      categoryId: 'c2',
      kind: 'income',
      amountCents: 45000,
      occurredAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Disponible: S/ 500.00'), findsOneWidget);
    bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.5, 0.001));
    expect((bar.valueColor as AlwaysStoppedAnimation<Color?>).value, Colors.white);

    await drainTimers(tester);
  });

  testWidgets('archivar una cuenta la oculta de la lista activa sin dialogo de confirmacion',
      (tester) async {
    await growTestSurface(tester);
    await db.accountsDao.upsert(AccountsCompanion.insert(
      id: 'a1',
      name: 'Ahorros',
      type: 'cash',
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Ahorros'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Archivar'));
    await tester.pumpAndSettle();

    expect(find.text('Ahorros'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing); // archivar no pide confirmacion

    final row = await (db.select(db.accounts)..where((a) => a.id.equals('a1'))).getSingle();
    expect(row.isArchived, isTrue);
    expect(row.deletedAt, isNull);

    await drainTimers(tester);
  });

  testWidgets('eliminar una cuenta pide confirmacion y hace softDelete', (tester) async {
    await growTestSurface(tester);
    await db.accountsDao.upsert(AccountsCompanion.insert(
      id: 'a1',
      name: 'Cuenta a borrar',
      type: 'cash',
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Cuenta a borrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Eliminar cuenta'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(find.text('Cuenta a borrar'), findsNothing);

    final row = await (db.select(db.accounts)..where((a) => a.id.equals('a1'))).getSingle();
    expect(row.deletedAt, isNotNull);

    await drainTimers(tester);
  });
}
