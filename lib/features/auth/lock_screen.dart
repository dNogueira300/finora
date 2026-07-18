import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/finora_colors.dart';
import '../../core/finora_tokens.dart';
import '../../core/finora_widgets.dart';
import '../../services/biometric_service.dart';
import 'auth_providers.dart';

final biometricServiceProvider = Provider((_) => BiometricService());
final appLockedProvider = StateProvider<bool>((_) => true);

/// Email del usuario autenticado para el saludo del bloqueo. Mismo criterio
/// que `currentUserEmailProvider` (settings) y `_currentUserEmail`
/// (dashboard): en los tests de widget no se llama a `Supabase.initialize()`
/// y `Supabase.instance` lanza, que aqui se trata como "sin email". Publico
/// (sin `_`) para poder fijarlo con un email de prueba en los tests de esta
/// pantalla, sin crear una dependencia circular hacia `settings_screen.dart`.
final lockUserEmailProvider = Provider<String?>((ref) {
  try {
    return Supabase.instance.client.auth.currentUser?.email;
  } on Object {
    return null;
  }
});

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
  }

  Future<void> _tryUnlock() async {
    final ok = await ref.read(biometricServiceProvider).authenticate();
    if (!mounted) return;
    if (ok) ref.read(appLockedProvider.notifier).state = false;
  }

  void _logout() {
    // Fire-and-forget: al emitir `signedOut`, el router resetea
    // `appLockedProvider` y redirige a `/login` (ver `RouterRefresh`).
    ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(lockUserEmailProvider);
    final name = email?.split('@').first;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: FinoraTokens.brandGradient),
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FinoraTokens.s24,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(FinoraTokens.s12),
                        decoration: BoxDecoration(
                          color: FinoraColors.surface,
                          borderRadius:
                              BorderRadius.circular(FinoraTokens.rCard),
                        ),
                        child: Semantics(
                          label: 'Finora',
                          image: true,
                          child: Image.asset(
                            'assets/brand/logo_inicio.png',
                            height: 96,
                          ),
                        ),
                      ),
                      const SizedBox(height: FinoraTokens.s32),
                      _Greeting(name: name),
                    ],
                  ),
                ),
              ),
            ),
            ContentSheet(
              padding: EdgeInsets.fromLTRB(
                FinoraTokens.s24,
                FinoraTokens.s24,
                FinoraTokens.s24,
                FinoraTokens.s24 + bottomInset,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _tryUnlock,
                      style: FilledButton.styleFrom(
                        backgroundColor: FinoraColors.primary,
                        foregroundColor: FinoraColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(FinoraTokens.rPill),
                        ),
                      ),
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Ingresar con huella digital'),
                    ),
                  ),
                  const SizedBox(height: FinoraTokens.s8),
                  TextButton(
                    onPressed: _logout,
                    style: TextButton.styleFrom(
                      foregroundColor: FinoraColors.textSecondary,
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saludo "Hola, {parte local del email}" con el nombre en negrita. Si no hay
/// email disponible (p. ej. sin sesion en tests) muestra solo "Hola".
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontSize: 22,
      color: FinoraColors.surface,
    );
    if (name == null || name!.isEmpty) {
      return const Text('Hola', textAlign: TextAlign.center, style: base);
    }
    return Text.rich(
      TextSpan(
        text: 'Hola, ',
        children: [
          TextSpan(
            text: name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: base,
    );
  }
}
