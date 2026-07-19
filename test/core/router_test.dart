import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:finora/core/router.dart';
import 'package:finora/core/finora_tokens.dart';

void main() {
  group('slideUpFadePage (transiciones de rutas push)', () {
    test('las rutas push usan CustomTransitionPage con dBase por defecto', () {
      final page = slideUpFadePage(
        key: const ValueKey('/add'),
        disableAnimations: false,
        child: const SizedBox(),
      );
      expect(page, isA<CustomTransitionPage<void>>());
      expect(page.transitionDuration, FinoraTokens.dBase);
      expect(page.reverseTransitionDuration, FinoraTokens.dBase);
    });

    test('con disableAnimations la duracion efectiva es cero', () {
      final page = slideUpFadePage(
        key: const ValueKey('/add'),
        disableAnimations: true,
        child: const SizedBox(),
      );
      expect(page.transitionDuration, Duration.zero);
      expect(page.reverseTransitionDuration, Duration.zero);
    });
  });

  group('slide-up + fade montado en el router (integracion)', () {
    // Arnes minimo GoRouter + MaterialApp.router (mismo patron que
    // app_shell_test), sin Supabase/auth: un home dummy que hace push de
    // `/dest`, cuya pagina se construye con `slideUpFadePage` leyendo
    // `MediaQuery.disableAnimations` igual que el router real. Asi el test
    // ejercita de verdad el `transitionsBuilder` (composicion fade>slide y la
    // curva), no solo el tipo de pagina.
    Widget buildApp({required bool disableAnimations}) {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => context.push('/dest'),
                    child: const Text('ir'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/dest',
            pageBuilder: (context, state) => slideUpFadePage(
              key: state.pageKey,
              disableAnimations: MediaQuery.disableAnimationsOf(context),
              child: const Scaffold(
                body: Center(child: Text('destino')),
              ),
            ),
          ),
        ],
      );
      return MaterialApp.router(
        routerConfig: router,
        builder: disableAnimations
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              )
            : null,
      );
    }

    testWidgets(
        'al hacer push, a mitad de la transicion el destino esta envuelto por '
        'FadeTransition > SlideTransition', (tester) async {
      await tester.pumpWidget(buildApp(disableAnimations: false));
      await tester.tap(find.text('ir'));
      await tester.pump(); // arranca la transicion
      await tester.pump(FinoraTokens.dBase ~/ 2); // a mitad de camino

      // Los dos widgets de la transicion existen mientras anima.
      expect(find.byType(SlideTransition), findsWidgets);
      expect(find.byType(FadeTransition), findsWidgets);

      // Composicion exacta de `slideUpFadePage`: el destino tiene un
      // SlideTransition ancestro, y ese slide esta envuelto por un
      // FadeTransition (fade por fuera, slide por dentro).
      final slideAroundDest = find.ancestor(
        of: find.text('destino'),
        matching: find.byType(SlideTransition),
      );
      expect(slideAroundDest, findsOneWidget);
      expect(
        find.ancestor(
          of: slideAroundDest,
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(find.text('destino'), findsOneWidget);
      expect(find.text('ir'), findsNothing);
    });

    testWidgets(
        'con disableAnimations el destino aparece al instante (un solo frame)',
        (tester) async {
      await tester.pumpWidget(buildApp(disableAnimations: true));
      await tester.tap(find.text('ir'));
      await tester.pump(); // duracion cero: el destino ya esta visible
      expect(find.text('destino'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('redirectDecision', () {
    test('sin sesion, en cualquier ubicacion distinta de /login -> /login', () {
      expect(
        redirectDecision(loggedIn: false, locked: false, location: '/'),
        '/login',
      );
      expect(
        redirectDecision(loggedIn: false, locked: true, location: '/lock'),
        '/login',
      );
      expect(
        redirectDecision(loggedIn: false, locked: false, location: '/settings'),
        '/login',
      );
    });

    test('sin sesion, ya en /login -> no redirige', () {
      expect(
        redirectDecision(loggedIn: false, locked: false, location: '/login'),
        isNull,
      );
      expect(
        redirectDecision(loggedIn: false, locked: true, location: '/login'),
        isNull,
      );
    });

    test('con sesion y bloqueado, fuera de /lock -> /lock', () {
      expect(
        redirectDecision(loggedIn: true, locked: true, location: '/'),
        '/lock',
      );
      expect(
        redirectDecision(loggedIn: true, locked: true, location: '/login'),
        '/lock',
      );
      expect(
        redirectDecision(loggedIn: true, locked: true, location: '/settings'),
        '/lock',
      );
    });

    test('con sesion y bloqueado, ya en /lock -> no redirige', () {
      expect(
        redirectDecision(loggedIn: true, locked: true, location: '/lock'),
        isNull,
      );
    });

    test('con sesion y desbloqueado, en /login o /lock -> /', () {
      expect(
        redirectDecision(loggedIn: true, locked: false, location: '/login'),
        '/',
      );
      expect(
        redirectDecision(loggedIn: true, locked: false, location: '/lock'),
        '/',
      );
    });

    test('con sesion y desbloqueado, en otra ruta -> no redirige', () {
      expect(
        redirectDecision(loggedIn: true, locked: false, location: '/'),
        isNull,
      );
      expect(
        redirectDecision(
            loggedIn: true, locked: false, location: '/settings'),
        isNull,
      );
      expect(
        redirectDecision(loggedIn: true, locked: false, location: '/add'),
        isNull,
      );
    });
  });
}
