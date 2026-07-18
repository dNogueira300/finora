import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finora/core/finora_colors.dart';
import 'package:finora/core/finora_tokens.dart';
import 'package:finora/core/finora_widgets.dart';

/// Tests de la fundacion de diseno del pulido UI (Tarea 1): valores exactos de
/// los tokens que consumen las tareas siguientes, y comportamiento de los
/// widgets base reutilizables (`Squircle`, `SectionHeader`). Los nombres y
/// valores aqui son un contrato: cambiarlos rompe las 9 tareas siguientes.
void main() {
  group('FinoraTokens: valores exactos', () {
    test('escala de espaciado (multiplos de 4)', () {
      expect(FinoraTokens.s4, 4.0);
      expect(FinoraTokens.s8, 8.0);
      expect(FinoraTokens.s12, 12.0);
      expect(FinoraTokens.s16, 16.0);
      expect(FinoraTokens.s20, 20.0);
      expect(FinoraTokens.s24, 24.0);
      expect(FinoraTokens.s32, 32.0);
    });

    test('radios', () {
      expect(FinoraTokens.rInput, 12.0);
      expect(FinoraTokens.rCard, 20.0);
      expect(FinoraTokens.rSquircle, 24.0);
      expect(FinoraTokens.rSheet, 28.0);
      expect(FinoraTokens.rPill, 999.0);
    });

    test('sombra suave unica', () {
      expect(FinoraTokens.shadowSoft, hasLength(1));
      final shadow = FinoraTokens.shadowSoft.first;
      expect(shadow.color, const Color(0x14000000));
      expect(shadow.blurRadius, 16);
      expect(shadow.offset, const Offset(0, 4));
    });

    test('duraciones y curva de motion', () {
      expect(FinoraTokens.dFast, const Duration(milliseconds: 150));
      expect(FinoraTokens.dBase, const Duration(milliseconds: 250));
      expect(FinoraTokens.dSlow, const Duration(milliseconds: 400));
      expect(FinoraTokens.curve, Curves.easeOutCubic);
    });

    test('degradado de marca usa primary -> primaryDark', () {
      expect(FinoraTokens.brandGradient.colors,
          [FinoraColors.primary, FinoraColors.primaryDark]);
      expect(FinoraTokens.brandGradient.begin, Alignment.topLeft);
      expect(FinoraTokens.brandGradient.end, Alignment.bottomRight);
    });
  });

  group('Squircle', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets('renderiza icono y label', (tester) async {
      await tester.pumpWidget(wrap(
        Squircle(icon: Icons.add, label: 'Agregar', onTap: () {}),
      ));

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Agregar'), findsOneWidget);
    });

    testWidgets('usa InkWell con splash (no GestureDetector) y dispara onTap',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(
        Squircle(icon: Icons.add, label: 'Agregar', onTap: () => taps++),
      ));

      expect(find.byType(InkWell), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('la variante highlighted cambia el fondo', (tester) async {
      BoxDecoration decorationOf(WidgetTester t) {
        final container = t.widget<Container>(find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(FinoraTokens.rSquircle),
        ));
        return container.decoration as BoxDecoration;
      }

      await tester.pumpWidget(wrap(
        Squircle(icon: Icons.add, label: 'Normal', onTap: () {}),
      ));
      final normal = decorationOf(tester);

      await tester.pumpWidget(wrap(
        Squircle(
            icon: Icons.add, label: 'Destacado', onTap: () {}, highlighted: true),
      ));
      final highlighted = decorationOf(tester);

      expect(normal.color, FinoraColors.surface);
      expect(highlighted.color, isNot(FinoraColors.surface));
      expect((highlighted.border as Border).top.color, FinoraColors.primary);
    });
  });

  group('SectionHeader', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('sin onSeeAll: muestra el titulo y no muestra boton',
        (tester) async {
      await tester.pumpWidget(wrap(const SectionHeader('Cuentas')));

      expect(find.text('Cuentas'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('con onSeeAll: muestra boton "Ver todos" con chevron y dispara',
        (tester) async {
      var seen = 0;
      await tester.pumpWidget(wrap(
        SectionHeader('Cuentas', onSeeAll: () => seen++),
      ));

      expect(find.byType(TextButton), findsOneWidget);
      expect(find.text('Ver todos'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(seen, 1);
    });
  });
}
