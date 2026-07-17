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

  testWidgets('muestra campos de email y contraseña con boton de login',
      (tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('el toggle cambia el texto del boton a Registrarme',
      (tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Registrarme'), findsNothing);

    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pump();

    expect(find.text('Registrarme'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsNothing);
  });
}
