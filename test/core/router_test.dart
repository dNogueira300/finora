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
