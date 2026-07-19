import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:finora/core/dates.dart';
import 'package:finora/core/money.dart';
import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/stats/stats_screen.dart';

void main() {
  // Ver nota equivalente en `test/accounts/cards_screen_test.dart`.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> growTestSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildApp() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es')],
        home: const StatsScreen(),
      ),
    );
  }

  // La misma logica que `_statsMonthProvider` (mes actual en hora de Lima)
  // para poder insertar datos de prueba que caigan dentro del mes que la
  // pantalla muestra por defecto.
  DateTime currentStatsMonth() {
    final now = toLima(DateTime.now().toUtc());
    return DateTime(now.year, now.month, 1);
  }

  // Un instante UTC que cae dentro del mes calendario de Lima [month]
  // (dia 15, a salvo de bordes de mes), tal como lo espera
  // `TransactionsDao.monthlyTotal`/`totalsByCategory` (usan `monthRangeUtc`).
  DateTime midMonthUtc(DateTime month) => limaToUtc(DateTime(month.year, month.month, 15));

  Future<void> seedCategory(String id, String name, int color) {
    return db.categoriesDao.upsert(CategoriesCompanion.insert(
      id: id,
      name: name,
      icon: 'restaurant',
      color: color,
      kind: 'expense',
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  // Marca una categoria ya sembrada como soft-deleted (deletedAt != null),
  // tal como la deja el borrado logico en la app: sus transacciones historicas
  // siguen existiendo pero `watchByKind` ya no la resuelve.
  Future<void> softDeleteCategory(String id) {
    return (db.update(db.categories)..where((c) => c.id.equals(id)))
        .write(CategoriesCompanion(deletedAt: Value(DateTime.now().toUtc())));
  }

  Future<void> seedTxn({
    required String id,
    required String categoryId,
    required String kind,
    required int amountCents,
    required DateTime occurredAt,
  }) {
    return db.transactionsDao.insertTxn(TransactionsCompanion.insert(
      id: id,
      accountId: 'acc1',
      categoryId: categoryId,
      kind: kind,
      amountCents: amountCents,
      occurredAt: occurredAt,
      updatedAt: DateTime.now().toUtc(),
    ));
  }

  testWidgets(
      'el donut y la leyenda muestran los gastos del mes actual por categoria '
      'con monto y porcentaje, y el centro el total del mes', (tester) async {
    await growTestSurface(tester);
    final month = currentStatsMonth();

    await seedCategory('catFood', 'Comida', 0xFFEF4444);
    await seedCategory('catTransport', 'Transporte', 0xFF3B82F6);
    await seedTxn(
      id: 't1',
      categoryId: 'catFood',
      kind: 'expense',
      amountCents: 6000,
      occurredAt: midMonthUtc(month),
    );
    await seedTxn(
      id: 't2',
      categoryId: 'catTransport',
      kind: 'expense',
      amountCents: 4000,
      occurredAt: midMonthUtc(month),
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(PieChart), findsOneWidget);

    // Centro del donut: total del mes (S/ 100.00).
    expect(find.text('Total del mes'), findsOneWidget);
    expect(find.text(formatMoney(10000)), findsOneWidget);

    // Leyenda: nombre, monto y porcentaje (60% / 40%) de cada categoria.
    expect(find.text('Comida'), findsOneWidget);
    expect(find.text(formatMoney(6000)), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('Transporte'), findsOneWidget);
    expect(find.text(formatMoney(4000)), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'las categorias soft-deleted se agrupan en UNA sola fila "Otros" en la '
      'leyenda con la suma de sus montos (fix minor T18)', (tester) async {
    await growTestSurface(tester);
    final month = currentStatsMonth();

    // Una categoria viva y DOS categorias soft-deleted, cada una con gasto.
    await seedCategory('catFood', 'Comida', 0xFFEF4444);
    await seedCategory('catGhostA', 'Fantasma A', 0xFF3B82F6);
    await seedCategory('catGhostB', 'Fantasma B', 0xFF8B5CF6);
    await seedTxn(
      id: 't1',
      categoryId: 'catFood',
      kind: 'expense',
      amountCents: 5000,
      occurredAt: midMonthUtc(month),
    );
    await seedTxn(
      id: 't2',
      categoryId: 'catGhostA',
      kind: 'expense',
      amountCents: 3000,
      occurredAt: midMonthUtc(month),
    );
    await seedTxn(
      id: 't3',
      categoryId: 'catGhostB',
      kind: 'expense',
      amountCents: 2000,
      occurredAt: midMonthUtc(month),
    );
    await softDeleteCategory('catGhostA');
    await softDeleteCategory('catGhostB');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // Una sola fila "Otros" con la suma de ambas soft-deleted (3000 + 2000).
    expect(find.text('Otros'), findsOneWidget);
    expect(find.text(formatMoney(5000)), findsWidgets); // Comida y Otros (misma suma)
    expect(find.text('50%'), findsWidgets); // Comida 50% y Otros 50%
    // Los nombres de las categorias borradas no aparecen.
    expect(find.text('Fantasma A'), findsNothing);
    expect(find.text('Fantasma B'), findsNothing);
    // La categoria viva sigue con su propia fila.
    expect(find.text('Comida'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'sin gastos en el mes muestra el mensaje vacio en vez del donut, y las '
      'barras de evolucion mensual igual se renderizan (en cero)', (tester) async {
    await growTestSurface(tester);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Sin gastos este mes'), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);
    expect(find.byType(BarChart), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'las barras de evolucion mensual muestran gasto vs ingreso de los '
      'ultimos 6 meses con las iniciales de mes en espanol', (tester) async {
    await growTestSurface(tester);
    final month = currentStatsMonth();
    final prevMonth = DateTime(month.year, month.month - 1, 1);
    final prevPrevMonth = DateTime(month.year, month.month - 2, 1);

    await seedCategory('catFood', 'Comida', 0xFFEF4444);
    await seedTxn(
      id: 't1',
      categoryId: 'catFood',
      kind: 'expense',
      amountCents: 5000,
      occurredAt: midMonthUtc(month),
    );
    await seedTxn(
      id: 't2',
      categoryId: 'catFood',
      kind: 'income',
      amountCents: 8000,
      occurredAt: midMonthUtc(month),
    );
    await seedTxn(
      id: 't3',
      categoryId: 'catFood',
      kind: 'expense',
      amountCents: 3000,
      occurredAt: midMonthUtc(prevMonth),
    );
    await seedTxn(
      id: 't4',
      categoryId: 'catFood',
      kind: 'income',
      amountCents: 2000,
      occurredAt: midMonthUtc(prevPrevMonth),
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('Evolución mensual'), findsOneWidget);
    expect(find.text('Gastos'), findsOneWidget);
    expect(find.text('Ingresos'), findsOneWidget);

    // Eje X: iniciales de mes en español de los 6 meses de la serie (el mes
    // actual y los 5 anteriores), tal como las calcula la propia pantalla.
    String monthLabel(DateTime m) {
      final raw = DateFormat.MMM('es').format(m);
      return raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
    }

    for (var i = 5; i >= 0; i--) {
      final m = DateTime(month.year, month.month - i, 1);
      expect(find.text(monthLabel(m)), findsWidgets);
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'los chevrons cambian de mes y recalculan el donut/leyenda del mes '
      'seleccionado', (tester) async {
    await growTestSurface(tester);
    final month = currentStatsMonth();
    final prevMonth = DateTime(month.year, month.month - 1, 1);

    // Dos categorias por mes (montos distintos entre si y del total) para
    // que el total del centro del donut no coincida por casualidad con el
    // monto de una fila de la leyenda.
    await seedCategory('catFood', 'Comida', 0xFFEF4444);
    await seedCategory('catTransport', 'Transporte', 0xFF3B82F6);
    await seedTxn(
      id: 't1',
      categoryId: 'catFood',
      kind: 'expense',
      amountCents: 6000,
      occurredAt: midMonthUtc(month),
    );
    await seedTxn(
      id: 't2',
      categoryId: 'catTransport',
      kind: 'expense',
      amountCents: 1000,
      occurredAt: midMonthUtc(month),
    );
    await seedTxn(
      id: 't3',
      categoryId: 'catFood',
      kind: 'expense',
      amountCents: 9000,
      occurredAt: midMonthUtc(prevMonth),
    );
    await seedTxn(
      id: 't4',
      categoryId: 'catTransport',
      kind: 'expense',
      amountCents: 500,
      occurredAt: midMonthUtc(prevMonth),
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    String monthHeaderLabel(DateTime m) {
      final raw = DateFormat('MMMM yyyy', 'es').format(m);
      return raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
    }

    expect(find.text(monthHeaderLabel(month)), findsOneWidget);
    expect(find.text(formatMoney(7000)), findsOneWidget); // total del mes actual (6000+1000)
    expect(find.text(formatMoney(6000)), findsOneWidget); // fila Comida
    expect(find.text(formatMoney(9000)), findsNothing);

    await tester.tap(find.byTooltip('Mes anterior'));
    await tester.pumpAndSettle();

    expect(find.text(monthHeaderLabel(prevMonth)), findsOneWidget);
    expect(find.text(formatMoney(9500)), findsOneWidget); // total del mes anterior (9000+500)
    expect(find.text(formatMoney(9000)), findsOneWidget); // fila Comida
    expect(find.text(formatMoney(6000)), findsNothing);
    expect(find.text(formatMoney(7000)), findsNothing);

    await tester.tap(find.byTooltip('Mes siguiente'));
    await tester.pumpAndSettle();

    expect(find.text(monthHeaderLabel(month)), findsOneWidget);
    expect(find.text(formatMoney(7000)), findsOneWidget);
    expect(find.text(formatMoney(6000)), findsOneWidget);
    expect(find.text(formatMoney(9000)), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
