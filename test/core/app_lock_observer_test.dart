import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finora/core/app_lock_observer.dart';
import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/auth/lock_screen.dart';
import 'package:finora/features/settings/settings_screen.dart';
import 'package:finora/services/biometric_service.dart';

/// Pruebas de `AppLockObserver` sin arbol de widgets ni router: se invoca
/// `didChangeAppLifecycleState` directamente sobre la instancia (mismo
/// patron que `test/sync/coordinator_test.dart` usa `ProviderContainer` puro
/// para lo que es observable sin depender de plugins de plataforma).
///
/// El observador lee `biometricEnabled` de la DB local de forma asincrona
/// (Task de re-bloqueo, requisito 4: no tocar Supabase), asi que tras cada
/// `didChangeAppLifecycleState` hay que drenar microtasks/():
///  - `settingsDao.get()` (drift) resuelve en una tarea asincrona real.
/// Se usa `await Future<void>.delayed(Duration.zero)` (repetido) para dar
/// tiempo a que esa cadena de futuros complete antes de leer
/// `appLockedProvider`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  const userId = 'u1';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> setBiometricEnabled(bool enabled) => db.settingsDao.upsert(
        UserSettingsCompanion(
          id: const Value(userId),
          biometricEnabled: Value(enabled),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  /// Da tiempo a que el `await settingsDao.get(...)` disparado dentro de
  /// `didChangeAppLifecycleState` (fire-and-forget) complete.
  Future<void> flushAsync() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ProviderContainer buildContainer({required BiometricService biometric}) {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      biometricServiceProvider.overrideWithValue(biometric),
      currentUserIdProvider.overrideWithValue(userId),
      // Arranca desbloqueada para poder observar la transicion a `true`.
    ]);
    container.read(appLockedProvider.notifier).state = false;
    addTearDown(container.dispose);
    return container;
  }

  test('biometricEnabled=true + logueado + paused -> appLocked pasa a true',
      () async {
    await setBiometricEnabled(true);
    final container = buildContainer(biometric: BiometricService());
    final observer = container.read(appLockObserverProvider);

    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    await flushAsync();

    expect(container.read(appLockedProvider), true);
  });

  test('biometricEnabled=false + paused -> se mantiene desbloqueada',
      () async {
    await setBiometricEnabled(false);
    final container = buildContainer(biometric: BiometricService());
    final observer = container.read(appLockObserverProvider);

    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    await flushAsync();

    expect(container.read(appLockedProvider), false);
  });

  test(
      'guard de autenticacion en curso: isAuthenticating=true + paused no '
      'bloquea; tras terminar (isAuthenticating=false) + paused si bloquea',
      () async {
    await setBiometricEnabled(true);
    final biometric = BiometricService();
    final container = buildContainer(biometric: biometric);
    final observer = container.read(appLockObserverProvider);

    // Simula que LockScreen/Settings estan en medio de un authenticate():
    // el sheet biometrico del sistema pausa la app momentaneamente.
    biometric.isAuthenticating = true;
    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    await flushAsync();
    expect(container.read(appLockedProvider), false);

    // `authenticate()` termina (su `finally` limpia la bandera) y luego la
    // app vuelve a pasar a background de verdad.
    biometric.isAuthenticating = false;
    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    await flushAsync();
    expect(container.read(appLockedProvider), true);
  });

  test('evento inactive nunca bloquea', () async {
    await setBiometricEnabled(true);
    final container = buildContainer(biometric: BiometricService());
    final observer = container.read(appLockObserverProvider);

    observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await flushAsync();

    expect(container.read(appLockedProvider), false);
  });

  test('sin usuario logueado + paused -> se mantiene desbloqueada', () async {
    await setBiometricEnabled(true);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      biometricServiceProvider.overrideWithValue(BiometricService()),
      currentUserIdProvider.overrideWithValue(null),
    ]);
    container.read(appLockedProvider.notifier).state = false;
    addTearDown(container.dispose);
    final observer = container.read(appLockObserverProvider);

    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    await flushAsync();

    expect(container.read(appLockedProvider), false);
  });
}
