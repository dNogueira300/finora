import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:finora/core/finora_colors.dart';
import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/alerts/alerts_dao_ext.dart';
import 'package:finora/features/alerts/alerts_screen.dart';

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
        home: const AlertsScreen(),
      ),
    );
  }

  group('AlertsDaoExt (DAO puro, sin widgets)', () {
    test(
        'insertAlert x2 -> watchAlerts emite ambas ordenadas desc; '
        'unreadCount 2 -> markAllRead -> unreadCount 0', () async {
      await db.insertAlert('Límite de gasto alcanzado', 'Superaste tu límite mensual');
      // Drift guarda `DateTimeColumn` como timestamp unix en segundos (sin
      // milisegundos) por defecto, asi que hace falta una pausa >= 1s para
      // que el segundo `createdAt` caiga en un segundo distinto del primero
      // y el orden desc sea determinista.
      await Future.delayed(const Duration(milliseconds: 1100));
      await db.insertAlert('Vencimiento de pago', 'Tu tarjeta vence mañana');

      final alerts = await db.watchAlerts().first;
      expect(alerts, hasLength(2));
      expect(alerts[0].title, 'Vencimiento de pago'); // mas reciente primero
      expect(alerts[1].title, 'Límite de gasto alcanzado');
      expect(alerts.every((a) => !a.isRead), isTrue);

      expect(await db.unreadCount().first, 2);

      await db.markAllRead();
      expect(await db.unreadCount().first, 0);
    });
  });

  group('AlertsScreen (widget)', () {
    testWidgets(
        'lista alertas de "límite" y "vencimiento" agrupadas en "Hoy" con su icono correcto',
        (tester) async {
      await growTestSurface(tester);
      await db.insertAlert('Límite de gasto alcanzado', 'Superaste tu límite mensual');
      await db.insertAlert('Vencimiento de pago', 'Tu tarjeta vence mañana');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // El encabezado del grupo se muestra en mayusculas.
      expect(find.text('HOY'), findsOneWidget);
      expect(find.text('Límite de gasto alcanzado'), findsOneWidget);
      expect(find.text('Superaste tu límite mensual'), findsOneWidget);
      expect(find.text('Vencimiento de pago'), findsOneWidget);
      expect(find.text('Tu tarjeta vence mañana'), findsOneWidget);

      // Icono ambar (campana) para "límite", icono azul (tarjeta) para
      // "vencimiento" (ver `_alertIcon` en `alerts_screen.dart`).
      expect(find.byIcon(Icons.notifications), findsOneWidget);
      expect(find.byIcon(Icons.credit_card), findsOneWidget);

      // Ambas alertas estan sin leer: cada fila muestra un dot primary.
      bool isUnreadDot(Widget w) =>
          w is Container &&
          (w.decoration as BoxDecoration?)?.color == FinoraColors.primary &&
          (w.decoration as BoxDecoration?)?.shape == BoxShape.circle;
      expect(find.byWidgetPredicate(isUnreadDot), findsNWidgets(2));

      await drainTimers(tester);
    });

    testWidgets('estado vacio muestra "Sin alertas por ahora"', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Sin alertas por ahora'), findsOneWidget);

      await drainTimers(tester);
    });

    testWidgets('"Marcar todas como leídas" pone isRead=true en todas las filas',
        (tester) async {
      await growTestSurface(tester);
      await db.insertAlert('Límite de gasto alcanzado', 'Superaste tu límite mensual');
      await db.insertAlert('Vencimiento de pago', 'Tu tarjeta vence mañana');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      var rows = await db.select(db.localAlerts).get();
      expect(rows.every((r) => !r.isRead), isTrue);

      await tester.tap(find.text('Marcar todas como leídas'));
      await tester.pumpAndSettle();

      rows = await db.select(db.localAlerts).get();
      expect(rows.every((r) => r.isRead), isTrue);

      await drainTimers(tester);
    });

    testWidgets('swipe-to-dismiss borra la alerta de la base de datos', (tester) async {
      await growTestSurface(tester);
      await db.insertAlert('Límite de gasto alcanzado', 'Superaste tu límite mensual');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Límite de gasto alcanzado'), findsOneWidget);
      expect(await db.select(db.localAlerts).get(), hasLength(1));

      await tester.drag(find.byType(Dismissible), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('Límite de gasto alcanzado'), findsNothing);
      expect(await db.select(db.localAlerts).get(), isEmpty);

      await drainTimers(tester);
    });
  });
}
