import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sync/sync_providers.dart';
import '../features/auth/lock_screen.dart';
import '../features/settings/settings_screen.dart';

/// Fuente del `AppLifecycleState` actual, indireccion sobre
/// `WidgetsBinding.instance.lifecycleState` para poder sobreescribirla en
/// tests (mismo patron de override que `databaseProvider`/
/// `biometricServiceProvider`): un test puede fijarla en `resumed` para
/// simular que el usuario ya volvio a primer plano mientras la lectura
/// asincrona de `AppLockObserver._maybeLock` estaba en curso.
final appLockLifecycleStateProvider = Provider<AppLifecycleState? Function()>(
  (ref) => () => WidgetsBinding.instance.lifecycleState,
);

/// Re-bloquea la app biometricamente cuando vuelve de segundo plano.
///
/// Antes de esto el bloqueo de huella solo se evaluaba en el arranque frio
/// (ver seed de `appLockedProvider` en `main.dart`). Este observador cubre el
/// otro caso: usuario sale de la app (Home, cambia de app, apaga pantalla) y
/// vuelve; si tiene la huella activada debe encontrar `/lock` de nuevo.
///
/// Implementado como clase propia (no se mezcla con `SyncCoordinator`, que ya
/// observa el ciclo de vida para disparar sync) para mantener el bloqueo y la
/// sincronizacion como responsabilidades separadas y testeables por su
/// cuenta.
///
/// Cuidados clave:
///  1. Solo reacciona a `AppLifecycleState.paused` (fondo real). `inactive`
///     tambien se dispara en overlays transitorios (barra de notificaciones,
///     selector de apps recientes, y el propio dialogo/sheet biometrico del
///     sistema operativo) y re-bloquear ahi seria demasiado agresivo.
///  2. Mientras `BiometricService.isAuthenticating` es true (autenticacion en
///     curso, ya sea desde `LockScreen._tryUnlock` o desde el switch de
///     Configuracion) se omite el re-bloqueo. El propio sheet biometrico del
///     sistema manda la app a `paused` momentaneamente mientras esta abierto;
///     sin este guard eso dispararia `appLocked = true` justo cuando el
///     usuario esta intentando desbloquear, produciendo un bucle
///     (bloquea -> LockScreen -> intenta desbloquear -> pausa -> bloquea de
///     nuevo -> ...).
///  3. `_maybeLock` lee `biometricEnabled` de forma asincrona (drift), asi
///     que entre el evento `paused` y el momento de bloquear puede pasar
///     tiempo suficiente para que el usuario ya haya vuelto a primer plano
///     (p. ej. solo abrio la barra de notificaciones y la cerro). Por eso
///     se re-chequea `appLockLifecycleStateProvider` justo antes de bloquear
///     y se aborta si ya no sigue en `paused`/`hidden` (fix de code review).
class AppLockObserver with WidgetsBindingObserver {
  AppLockObserver(this._ref) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref _ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) return;
    if (_ref.read(biometricServiceProvider).isAuthenticating) return;
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    unawaited(_maybeLock(userId));
  }

  /// `biometricEnabled` se lee de la DB local (no de Supabase, ver Task de
  /// re-bloqueo): es la misma fuente que usa `main.dart` para sembrar
  /// `appLockedProvider` en el arranque frio, y refleja cambios hechos en
  /// Configuracion durante la sesion (a diferencia de un valor cacheado en
  /// memoria al inicio).
  ///
  /// Todo el cuerpo va envuelto en try/catch (best-effort, mismo criterio
  /// que el resto de los hooks de ciclo de vida de la app, p. ej.
  /// `SyncCoordinator.trigger`): una lectura que falla durante un teardown
  /// (DB ya cerrada, container ya disposed) no debe surgir como un error
  /// asincrono sin manejar.
  Future<void> _maybeLock(String userId) async {
    try {
      final settings = await _ref.read(databaseProvider).settingsDao.get(userId);
      if (settings?.biometricEnabled != true) return;
      // Re-chequeo tras el `await`: si mientras se leia la DB arranco una
      // autenticacion, no forzar el bloqueo encima de ese intento.
      if (_ref.read(biometricServiceProvider).isAuthenticating) return;
      // Re-chequeo del ciclo de vida (fix de review): el `await` de arriba
      // puede tardar lo suficiente como para que el usuario ya haya vuelto
      // a primer plano (p. ej. solo abrio la barra de notificaciones y la
      // cerro de nuevo). Sin esto, el bloqueo llegaria tarde y lo
      // encontraria a mitad de una tarea, con un redirect a /lock
      // espurio. Solo se bloquea si la app sigue realmente en background
      // (`paused` o `hidden`, no `resumed`/`inactive`).
      final lifecycle = _ref.read(appLockLifecycleStateProvider)();
      if (lifecycle != AppLifecycleState.paused &&
          lifecycle != AppLifecycleState.hidden) {
        return;
      }
      // Re-chequeo de sesion: si cerro sesion mientras se leia la DB, no
      // forzar un bloqueo obsoleto (RouterRefresh ya resetea
      // appLockedProvider a false en signedOut, pero evita la carrera de
      // reescribirlo a true despues de eso).
      if (_ref.read(currentUserIdProvider) == null) return;
      // Idempotente: si ya estaba bloqueada (p. ej. ya en /lock o /login)
      // esto no genera un segundo redirect, `redirectDecision` ya es un
      // no-op en ese caso.
      _ref.read(appLockedProvider.notifier).state = true;
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // Best-effort: ver docstring del metodo.
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// Construccion perezosa, mismo patron que `syncCoordinatorProvider`: solo se
/// instancia (y por lo tanto solo registra el `WidgetsBindingObserver`)
/// cuando algun widget hace `ref.watch(appLockObserverProvider)` en
/// `FinoraApp.build`.
final appLockObserverProvider = Provider<AppLockObserver>((ref) {
  final o = AppLockObserver(ref);
  ref.onDispose(o.dispose);
  return o;
});
