import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:finora/core/app_shell.dart';
import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/accounts/cards_screen.dart';

/// Reproduce el bug reportado: "+ congela la app en /cards" y "el icono de
/// calendario desde tarjetas cuelga la app" (mismo origen). El shell
/// (`AppShell`) tiene un `FloatingActionButton` y `CardsScreen` tiene su
/// propio `FloatingActionButton.extended`; ninguno declara `heroTag`
/// explicito, asi que ambos reciben el mismo tag por defecto de Flutter.
/// Cuando ambos coexisten en el arbol de /cards y se hace push de CUALQUIER
/// ruta encima, la transiccion de Hero escanea el subarbol saliente y
/// encuentra dos Heroes con el mismo tag, lanzando
/// "There are multiple heroes that share the same tag within a subtree" a
/// mitad de la transicion (la app "se congela").
void main() {
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

  Widget buildApp(GoRouter router) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es')],
      ),
    );
  }

  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: '/cards',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Center(child: Text('Dummy Home'))),
            ),
            GoRoute(path: '/cards', builder: (_, _) => const CardsScreen()),
          ],
        ),
        GoRoute(
          path: '/calendar',
          builder: (_, _) => const Scaffold(body: Center(child: Text('Calendario dummy'))),
        ),
      ],
    );
  }

  testWidgets(
      'tocar el icono de calendario desde /cards navega sin lanzar '
      'excepcion de Heroes duplicados', (tester) async {
    await growTestSurface(tester);
    final router = buildRouter();
    await tester.pumpWidget(buildApp(router));
    await tester.pumpAndSettle();

    // Ambos FABs (el circular del shell y el extendido de CardsScreen)
    // estan presentes simultaneamente en /cards: esa coexistencia es la
    // precondicion del bug.
    expect(find.byType(FloatingActionButton), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();

    // Antes de la correccion, la transiccion de Hero lanza
    // "multiple heroes that share the same tag within a subtree" y la
    // navegacion nunca completa.
    expect(tester.takeException(), isNull);
    expect(find.text('Calendario dummy'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'presionar el FAB del shell desde /cards navega a /add sin lanzar '
      'excepcion de Heroes duplicados', (tester) async {
    await growTestSurface(tester);
    final router = GoRouter(
      initialLocation: '/cards',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Center(child: Text('Dummy Home'))),
            ),
            GoRoute(path: '/cards', builder: (_, _) => const CardsScreen()),
          ],
        ),
        GoRoute(
          path: '/add',
          builder: (_, _) => const Scaffold(body: Center(child: Text('Add dummy'))),
        ),
      ],
    );
    await tester.pumpWidget(buildApp(router));
    await tester.pumpAndSettle();

    // El FAB del shell es el circular (no extendido); el de `CardsScreen`
    // ("Nueva cuenta") es `FloatingActionButton.extended` (`isExtended ==
    // true`). Se distingue por esa propiedad en vez del orden en el arbol,
    // que no esta garantizado.
    await tester.tap(find.byWidgetPredicate(
      (w) => w is FloatingActionButton && !w.isExtended,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Add dummy'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
