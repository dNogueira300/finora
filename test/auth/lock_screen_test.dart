import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/features/auth/lock_screen.dart';
import 'package:finora/services/biometric_service.dart';

/// `BiometricService` de prueba: evita tocar el plugin `local_auth` (no
/// disponible en el entorno de test) cuando `LockScreen.initState` lanza el
/// intento de desbloqueo automatico.
class _FakeBiometric extends BiometricService {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> authenticate() async => false;
}

void main() {
  Widget buildApp() {
    return ProviderScope(
      overrides: [
        biometricServiceProvider.overrideWithValue(_FakeBiometric()),
        lockUserEmailProvider.overrideWithValue('eliasdna0499@gmail.com'),
      ],
      child: const MaterialApp(home: LockScreen()),
    );
  }

  testWidgets(
      'muestra el CTA de huella y el saludo con la parte local del email',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump(); // corre el postFrameCallback de _tryUnlock

    expect(find.text('Ingresar con huella digital'), findsOneWidget);
    expect(find.textContaining('eliasdna0499'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });
}
