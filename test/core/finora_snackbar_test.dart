import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finora/core/finora_colors.dart';
import 'package:finora/core/finora_snackbar.dart';

/// Tests de las notificaciones (toasts) personalizadas: cada variante muestra
/// su mensaje, el icono correcto y el color de acento correspondiente; el
/// toast cae desde la parte superior; y pedir uno nuevo reemplaza al anterior
/// en vez de acumular una cola.
void main() {
  // Monta un boton que, al pulsarlo, dispara el toast [onTap]. La MaterialApp
  // aporta el Overlay raiz donde se inserta.
  Widget host(void Function(BuildContext) onTap) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onTap(context),
            child: const Text('mostrar'),
          ),
        ),
      ),
    );
  }

  // Dispara el toast y deja que termine la animacion de entrada.
  Future<void> show(WidgetTester tester) async {
    await tester.tap(find.text('mostrar'));
    await tester.pump(); // inserta la entrada del overlay
    await tester.pump(const Duration(milliseconds: 300)); // entrada deslizante
  }

  // Deja pasar el auto-descarte para no dejar timers/animaciones pendientes.
  Future<void> cleanup(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3)); // dispara el temporizador
    await tester.pumpAndSettle(); // salida + retiro de la entrada
  }

  testWidgets('success: mensaje, check verde de marca', (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.success(c, 'Creado')));
    await show(tester);

    expect(find.text('Creado'), findsOneWidget);
    final icon = _icon(Icons.check_circle_rounded);
    expect(icon.color, FinoraColors.primary);

    await cleanup(tester);
  });

  testWidgets('error: mensaje, icono de error rojo', (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.error(c, 'Fallo')));
    await show(tester);

    expect(find.text('Fallo'), findsOneWidget);
    expect(_icon(Icons.error_rounded).color, FinoraColors.expense);

    await cleanup(tester);
  });

  testWidgets('info: mensaje, icono info azul', (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.info(c, 'Aviso')));
    await show(tester);

    expect(find.text('Aviso'), findsOneWidget);
    expect(_icon(Icons.info_rounded).color, FinoraColors.savings);

    await cleanup(tester);
  });

  testWidgets('warning: mensaje, icono de advertencia ambar', (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.warning(c, 'Cuidado')));
    await show(tester);

    expect(find.text('Cuidado'), findsOneWidget);
    expect(_icon(Icons.warning_amber_rounded).color, FinoraColors.warning);

    await cleanup(tester);
  });

  testWidgets('el toast cae desde la parte superior', (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.success(c, 'Creado')));
    await show(tester);

    // Ya asentado arriba: el borde superior del texto queda en la franja
    // superior de la pantalla (800px de alto por defecto en tests).
    final dy = tester.getTopLeft(find.text('Creado')).dy;
    expect(dy, lessThan(150));

    await cleanup(tester);
  });

  testWidgets('un segundo toast reemplaza al primero (no acumula)',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    FinoraSnackbar.info(ctx, 'Primero');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Primero'), findsOneWidget);

    FinoraSnackbar.error(ctx, 'Segundo');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Primero'), findsNothing);
    expect(find.text('Segundo'), findsOneWidget);

    await cleanup(tester);
  });
}

// Unico Icon visible en el arbol pertenece al toast (el boton no tiene icono).
Icon _icon(IconData data) {
  final finder = find.byIcon(data);
  expect(finder, findsOneWidget);
  return finder.evaluate().single.widget as Icon;
}
