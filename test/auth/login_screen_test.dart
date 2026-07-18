import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/features/auth/login_screen.dart';

void main() {
  Widget buildApp() {
    return const ProviderScope(
      child: MaterialApp(home: LoginScreen()),
    );
  }

  testWidgets('muestra campos de email y contraseña con el CTA Ingresar y el logo',
      (tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Ingresar'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/brand/logo_inicio.png')),
      findsOneWidget,
    );
  });

  testWidgets('el toggle cambia el CTA a Crear cuenta', (tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.widgetWithText(FilledButton, 'Ingresar'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Crear cuenta'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Crear cuenta'));
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Crear cuenta'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Ingresar'), findsNothing);
  });
}
