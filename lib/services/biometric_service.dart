import 'package:local_auth/local_auth.dart';

class BiometricService {
  final _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
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
    }
  }
}
