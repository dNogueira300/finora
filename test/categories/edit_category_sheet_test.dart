import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/categories/edit_category_sheet.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  /// El sheet completo (nombre + tipo + iconos + colores + boton) no entra en
  /// la superficie por defecto (800x600); se agranda para que "Guardar" quede
  /// visible sin scroll (mismo criterio que add_transaction_screen_test).
  Future<void> growTestSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> drainTimers(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Widget buildApp({String initialKind = 'expense'}) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: EditCategorySheet(initialKind: initialKind),
        ),
      ),
    );
  }

  testWidgets('guardar con nombre valido inserta la categoria del kind inicial',
      (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp(initialKind: 'expense'));

    await tester.enterText(
        find.widgetWithText(TextField, 'Nombre'), 'Mascotas');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pump(const Duration(milliseconds: 100));

    final rows = await db.select(db.categories).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Mascotas');
    expect(rows.single.kind, 'expense');

    await drainTimers(tester);
  });

  testWidgets('cambiar el tipo a Ingreso guarda kind=income', (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp(initialKind: 'expense'));

    await tester.enterText(
        find.widgetWithText(TextField, 'Nombre'), 'Freelance');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ingreso'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pump(const Duration(milliseconds: 100));

    final rows = await db.select(db.categories).get();
    expect(rows, hasLength(1));
    expect(rows.single.kind, 'income');

    await drainTimers(tester);
  });

  testWidgets('guardar sin nombre muestra el SnackBar y no inserta nada',
      (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp());

    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pump();

    expect(find.text('Ingresa un nombre'), findsOneWidget);
    expect(await db.select(db.categories).get(), isEmpty);

    await drainTimers(tester);
  });
}
