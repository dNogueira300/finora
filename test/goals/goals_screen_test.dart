import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/goals/goals_screen.dart';

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

  // El listado de metas + FAB no entra en el tamaño de superficie por
  // defecto de los tests (800x600): se agranda (mismo patron que
  // `cards_screen_test.dart`).
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
        home: const GoalsScreen(),
      ),
    );
  }

  testWidgets('crear una meta desde el FAB la muestra en la lista con sus montos',
      (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(
      find.text('Aún no tienes metas.\nToca "Nueva meta" para crear la primera.'),
      findsOneWidget,
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // "Nombre" es el primer TextField del formulario y "Monto objetivo" el
    // segundo (mismo patron que `cards_screen_test.dart`, que usa
    // `find.byType(TextField).first` para el campo nombre).
    await tester.enterText(find.byType(TextField).at(0), 'Vacaciones');
    await tester.enterText(find.byType(TextField).at(1), '1000');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Vacaciones'), findsOneWidget);
    expect(find.text('S/ 0.00 ahorrado de S/ 1,000.00'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);

    final rows = await db.select(db.savingsGoals).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Vacaciones');
    expect(rows.single.targetCents, 100000);
    expect(rows.single.savedCents, 0);

    await drainTimers(tester);
  });

  testWidgets(
      'abonar a "Laptop" (objetivo S/ 3,500) con S/ 500 suma 50000 centavos y muestra 14%',
      (tester) async {
    await growTestSurface(tester);
    await db.goalsDao.upsert(SavingsGoalsCompanion.insert(
      id: 'g1',
      name: 'Laptop',
      targetCents: 350000, // S/ 3,500.00
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Abonar'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), '500');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Abonar'));
    await tester.pumpAndSettle();

    final row = await (db.select(db.savingsGoals)..where((g) => g.id.equals('g1'))).getSingle();
    expect(row.savedCents, 50000);

    expect(find.text('14%'), findsOneWidget);
    expect(find.text('S/ 500.00 ahorrado de S/ 3,500.00'), findsOneWidget);

    await drainTimers(tester);
  });

  testWidgets('un monto invalido en "Abonar" muestra un SnackBar y no modifica savedCents',
      (tester) async {
    await growTestSurface(tester);
    await db.goalsDao.upsert(SavingsGoalsCompanion.insert(
      id: 'g1',
      name: 'Laptop',
      targetCents: 350000,
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Abonar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'no-es-un-numero');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Abonar'));
    await tester.pumpAndSettle();

    expect(find.text('Monto inválido'), findsOneWidget);

    final row = await (db.select(db.savingsGoals)..where((g) => g.id.equals('g1'))).getSingle();
    expect(row.savedCents, 0);

    await drainTimers(tester);
  });

  testWidgets('editar una meta existente pre-llena el formulario y mantiene el mismo id',
      (tester) async {
    await growTestSurface(tester);
    await db.goalsDao.upsert(SavingsGoalsCompanion.insert(
      id: 'g1',
      name: 'Meta vieja',
      targetCents: 100000,
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Editar'));
    await tester.pumpAndSettle();

    final nameField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(nameField.controller?.text, 'Meta vieja');
    expect(find.text('1000.00'), findsOneWidget); // monto objetivo precargado

    await tester.enterText(find.byType(TextField).at(0), 'Meta nueva');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Meta nueva'), findsOneWidget);
    expect(find.text('Meta vieja'), findsNothing);

    final rows = await db.select(db.savingsGoals).get();
    expect(rows, hasLength(1)); // se actualizo la fila existente, no se creo una nueva
    expect(rows.single.id, 'g1');
    expect(rows.single.name, 'Meta nueva');

    await drainTimers(tester);
  });

  testWidgets('eliminar una meta pide confirmacion y hace softDelete', (tester) async {
    await growTestSurface(tester);
    await db.goalsDao.upsert(SavingsGoalsCompanion.insert(
      id: 'g1',
      name: 'Meta a borrar',
      targetCents: 100000,
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Eliminar meta'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(find.text('Meta a borrar'), findsNothing);

    final row = await (db.select(db.savingsGoals)..where((g) => g.id.equals('g1'))).getSingle();
    expect(row.deletedAt, isNotNull);

    await drainTimers(tester);
  });
}
