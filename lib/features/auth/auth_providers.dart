import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_repository.dart';

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(Supabase.instance.client));

final authStateProvider = StreamProvider<AuthState>(
    (ref) => ref.watch(authRepositoryProvider).onAuthStateChange);
