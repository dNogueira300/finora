import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/transactions/add_transaction_screen.dart';

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

  /// El formulario completo (toggle + monto + chips + cuenta + fecha + nota
  /// + boton) no entra en el tamaño de superficie por defecto de los tests
  /// (800x600): el `ListView` es perezoso y no construye el boton "Guardar"
  /// si queda fuera del viewport, haciendo que los finders no lo encuentren.
  /// Se agranda la superficie de prueba para que todo el contenido quede
  /// visible sin necesidad de hacer scroll manual en cada test.
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

  Widget buildPlainApp() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es')],
        home: const AddTransactionScreen(),
      ),
    );
  }

  testWidgets(
      'con categoria y cuenta sembradas: monto valido + chip + cuenta + Guardar inserta la transaccion',
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

    // Para que `context.pop()` (extension de go_router) no lance "No
    // GoRouter found in context" al guardar con exito, se envuelve la
    // pantalla en un GoRouter real con dos rutas y se navega a `/add` antes
    // de interactuar, de forma que el pop tenga a donde volver.
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/add', builder: (_, _) => const AddTransactionScreen()),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es')],
      ),
    ));
    await tester.pumpAndSettle();

    router.push('/add');
    await tester.pumpAndSettle();

    // El campo de monto es el primer TextField del arbol (el de nota, mas
    // abajo, tiene el label "Nota (opcional)").
    await tester.enterText(find.byType(TextField).first, '45.50');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Comida'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuenta principal (Efectivo)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pumpAndSettle();

    // El pop tuvo exito: se ve de nuevo la pantalla "home".
    expect(find.text('home'), findsOneWidget);

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(1));
    expect(rows.single.amountCents, 4550);
    expect(rows.single.kind, 'expense');
    expect(rows.single.accountId, 'a1');
    expect(rows.single.categoryId, 'c1');

    await drainTimers(tester);
  });

  testWidgets('monto invalido muestra SnackBar "Monto inválido" y no inserta nada',
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
      name: 'Efectivo',
      type: 'cash',
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildPlainApp());
    await tester.pumpAndSettle();

    // No se ingresa nada de monto (texto vacio -> parseMoney null).
    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Monto inválido'), findsOneWidget);

    final rows = await db.select(db.transactions).get();
    expect(rows, isEmpty);

    await drainTimers(tester);
  });

  testWidgets('sin cuentas: Guardar deshabilitado y se muestra el hint', (tester) async {
    await growTestSurface(tester);
    await db.categoriesDao.upsert(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Comida',
      icon: 'restaurant',
      color: 0xFFEF4444,
      kind: 'expense',
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildPlainApp());
    await tester.pumpAndSettle();

    expect(find.text('Crea una cuenta primero en Mis tarjetas'), findsOneWidget);

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Guardar'));
    expect(button.onPressed, isNull);

    final rows = await db.select(db.transactions).get();
    expect(rows, isEmpty);

    await drainTimers(tester);
  });
}
