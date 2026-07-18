import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sync/sync_providers.dart';
import '../features/auth/lock_screen.dart';
import '../features/settings/settings_screen.dart';

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
/// Dos cuidados clave:
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
  Future<void> _maybeLock(String userId) async {
    final settings = await _ref.read(databaseProvider).settingsDao.get(userId);
    if (settings?.biometricEnabled != true) return;
    // Re-chequeo tras el `await`: si mientras se leia la DB arranco una
    // autenticacion, no forzar el bloqueo encima de ese intento.
    if (_ref.read(biometricServiceProvider).isAuthenticating) return;
    // Idempotente: si ya estaba bloqueada (p. ej. ya en /lock o /login) esto
    // no genera un segundo redirect, `redirectDecision` ya es un no-op en
    // ese caso.
    _ref.read(appLockedProvider.notifier).state = true;
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
