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
}
