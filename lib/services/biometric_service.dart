import 'package:local_auth/local_auth.dart';

class BiometricService {
  final _auth = LocalAuthentication();

  /// True mientras un `authenticate()` esta en curso (LockScreen intentando
  /// desbloquear, o el switch de Configuracion pidiendo confirmacion antes de
  /// activar la huella). `AppLockObserver` lo consulta para no re-bloquear la
  /// app cuando el propio sheet biometrico del sistema operativo la manda a
  /// segundo plano momentaneamente: sin este guard, ese `paused` transitorio
  /// forzaria `appLocked = true` y produciria un bucle (bloquea -> LockScreen
  /// -> intenta desbloquear -> pausa -> bloquea de nuevo...).
  bool isAuthenticating = false;

  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    isAuthenticating = true;
    try {
      // local_auth 3.x reemplazo AuthenticationOptions por parametros
      // directos en `authenticate`: stickyAuth -> persistAcrossBackgrounding.
      return await _auth.authenticate(
        localizedReason: 'Desbloquea Finora con tu huella digital',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    } finally {
      isAuthenticating = false;
    }
  }
}
