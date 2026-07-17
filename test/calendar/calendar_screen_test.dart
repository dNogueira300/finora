import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:finora/core/dates.dart';
import 'package:finora/core/finora_colors.dart';
import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/calendar/calendar_screen.dart';
import 'package:finora/features/calendar/due_dates.dart';

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
        home: const CalendarScreen(),
      ),
    );
  }

  bool isDot(Widget w, Color color) =>
      w is Container && (w.decoration as BoxDecoration?)?.color == color;

  testWidgets(
      'una cuenta de credito con dia de pago 15 y cierre 30 muestra ambos '
      'marcadores en el grid y ambas filas en "Proximos vencimientos"',
      (tester) async {
    await growTestSurface(tester);
    await db.accountsDao.upsert(AccountsCompanion.insert(
      id: 'cc1',
      name: 'Visa Oro',
      type: 'credit',
      paymentDueDay: const Value(15),
      statementDay: const Value(30),
      last4: const Value('4242'),
      updatedAt: DateTime.now().toUtc(),
    ));

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // Grid: el dia 15 (pago, punto rojo) y el dia 30 -o su version ajustada
    // a un mes corto- (cierre, punto ambar) quedan marcados en el mes
    // mostrado (el mes actual, con una unica cuenta de credito).
    expect(
      find.descendant(of: find.byType(GridView), matching: find.byWidgetPredicate((w) => isDot(w, FinoraColors.expense))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(GridView), matching: find.byWidgetPredicate((w) => isDot(w, FinoraColors.warning))),
      findsOneWidget,
    );

    // Lista "Proximos vencimientos": una fila de Pago y otra de Cierre, cada
    // una con la fecha (`nextDueDate`) y el conteo de dias restantes que
    // calcula la propia pantalla.
    final today = toLima(DateTime.now().toUtc());
    final todayDate = DateTime(today.year, today.month, today.day);
    final pagoDate = nextDueDate(15, todayDate);
    final cierreDate = nextDueDate(30, todayDate);
    final pagoDays = pagoDate.difference(todayDate).inDays;
    final cierreDays = cierreDate.difference(todayDate).inDays;
    String daysLabel(int days) =>
        days <= 0 ? 'Vence hoy' : 'Vence en $days día${days == 1 ? '' : 's'}';

    expect(find.text('Visa Oro'), findsNWidgets(2)); // fila de Pago + fila de Cierre
    expect(find.text('Pago · ${DateFormat('d MMMM', 'es').format(pagoDate)}'), findsOneWidget);
    expect(find.text('Cierre · ${DateFormat('d MMMM', 'es').format(cierreDate)}'), findsOneWidget);
    expect(find.text(daysLabel(pagoDays)), findsOneWidget);
    expect(find.text(daysLabel(cierreDays)), findsOneWidget);

    // Los puntos de color de cada fila (leading del ListTile dentro de su
    // Card) coinciden con los del grid.
    expect(
      find.descendant(of: find.byType(Card), matching: find.byWidgetPredicate((w) => isDot(w, FinoraColors.expense))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(Card), matching: find.byWidgetPredicate((w) => isDot(w, FinoraColors.warning))),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('sin cuentas de credito muestra el mensaje vacio en "Proximos vencimientos"',
      (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(
      find.text('No tienes tarjetas de crédito con fechas de pago o\ncierre configuradas.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
