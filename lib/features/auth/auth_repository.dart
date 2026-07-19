import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signUp(String email, String password) =>
      _client.auth.signUp(email: email, password: password);

  Future<void> signOut() => _client.auth.signOut();

  /// Guarda el alias del usuario en los metadatos de auth (`user_metadata`).
  /// Al completar, Supabase emite un evento `userUpdated` en
  /// [onAuthStateChange], que refresca los providers que leen el alias.
  Future<void> updateAlias(String alias) =>
      _client.auth.updateUser(UserAttributes(data: {'alias': alias}));

  /// Cambia la contraseña del usuario autenticado (no necesita correo:
  /// la sesion vigente autoriza el cambio). Usado por "Cambiar contraseña"
  /// en Perfil.
  Future<void> updatePassword(String newPassword) =>
      _client.auth.updateUser(UserAttributes(password: newPassword));

  /// Envia el correo de recuperacion con el codigo (OTP) de 6 digitos.
  /// Requiere que la plantilla "Reset Password" del proyecto Supabase
  /// incluya `{{ .Token }}` (ver flujo en `login_screen._ResetPasswordDialog`).
  Future<void> sendPasswordResetCode(String email) =>
      _client.auth.resetPasswordForEmail(email);

  /// Canjea el codigo del correo (`verifyOTP` tipo recovery, que ademas
  /// inicia sesion) y fija la nueva contraseña. Tras esto el usuario queda
  /// autenticado y el router lo lleva al inicio.
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _client.auth.verifyOTP(
      type: OtpType.recovery,
      email: email,
      token: code,
    );
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}
