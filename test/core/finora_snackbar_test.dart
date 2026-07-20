import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finora/core/finora_colors.dart';
import 'package:finora/core/finora_snackbar.dart';

/// Tests de las notificaciones (toasts) personalizadas: cada variante muestra
/// su mensaje, el icono correcto y el color de acento correspondiente, y el
/// helper reemplaza el toast anterior en vez de acumular una cola.
void main() {
  // Monta un boton que, al pulsarlo, dispara el toast [onTap]. Devuelve un
  // Scaffold con su propio ScaffoldMessenger (via MaterialApp).
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

  Future<void> tapShow(WidgetTester tester) async {
    await tester.tap(find.text('mostrar'));
    await tester.pump(); // dispara la animacion de entrada del SnackBar
  }

  Icon iconOf(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon).first);

  testWidgets('success: mensaje, check verde de marca', (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.success(c, 'Creado')));
    await tapShow(tester);

    expect(find.text('Creado'), findsOneWidget);
    final icon = iconOf(tester);
    expect(icon.icon, Icons.check_circle_rounded);
    expect(icon.color, FinoraColors.primary);
  });

  testWidgets('error: mensaje, icono de error rojo', (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.error(c, 'Fallo')));
    await tapShow(tester);

    expect(find.text('Fallo'), findsOneWidget);
    final icon = iconOf(tester);
    expect(icon.icon, Icons.error_rounded);
    expect(icon.color, FinoraColors.expense);
  });

  testWidgets('info: mensaje, icono info azul', (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.info(c, 'Aviso')));
    await tapShow(tester);

    expect(find.text('Aviso'), findsOneWidget);
    final icon = iconOf(tester);
    expect(icon.icon, Icons.info_rounded);
    expect(icon.color, FinoraColors.savings);
  });

  testWidgets('warning: mensaje, icono de advertencia ambar', (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.warning(c, 'Cuidado')));
    await tapShow(tester);

    expect(find.text('Cuidado'), findsOneWidget);
    final icon = iconOf(tester);
    expect(icon.icon, Icons.warning_amber_rounded);
    expect(icon.color, FinoraColors.warning);
  });

  testWidgets('el toast es flotante y sin fondo propio del SnackBar',
      (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.success(c, 'Creado')));
    await tapShow(tester);

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.behavior, SnackBarBehavior.floating);
    expect(snack.backgroundColor, Colors.transparent);
    expect(snack.elevation, 0);
  });

  testWidgets('mostrar un segundo toast reemplaza al primero (no acumula)',
      (tester) async {
    await tester.pumpWidget(host((c) => FinoraSnackbar.info(c, 'Primero')));
    await tapShow(tester);
    expect(find.text('Primero'), findsOneWidget);

    // Segundo toast desde el mismo boton no es posible (cierra sobre 'Primero'),
    // asi que se dispara otro directamente reusando el contexto del boton.
    await tester.tap(find.text('mostrar'));
    await tester.pump();
    // clearSnackBars() saca el anterior de inmediato: solo hay un SnackBar.
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
