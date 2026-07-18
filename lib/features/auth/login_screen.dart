import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/finora_colors.dart';
import '../../core/finora_tokens.dart';
import '../../core/finora_widgets.dart';
import 'auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    final auth = ref.read(authRepositoryProvider);
    try {
      if (_isRegister) {
        await auth.signUp(_email.text.trim(), _password.text);
      } else {
        await auth.signIn(_email.text.trim(), _password.text);
      }
      // La navegación la maneja el redirect del router (Task 10).
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Copy segun la parte del flujo: el CTA primario y el enlace de texto
    // intercambian "Ingresar" / "Crear cuenta".
    final primaryLabel = _isRegister ? 'Crear cuenta' : 'Ingresar';
    final toggleLabel = _isRegister ? 'Ingresar' : 'Crear cuenta';

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: FinoraTokens.brandGradient),
        child: SafeArea(
          bottom: false,
          // Patron canonico para que el formulario siga siendo usable con el
          // teclado abierto: el contenido rellena el viewport cuando hay
          // espacio (IntrinsicHeight + Expanded) y hace scroll cuando el
          // teclado lo reduce (SingleChildScrollView + minHeight).
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: FinoraTokens.s32,
                        ),
                        child: Center(child: _BrandLogo()),
                      ),
                      Expanded(
                        child: ContentSheet(
                          padding: const EdgeInsets.all(FinoraTokens.s24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _isRegister
                                    ? 'Crea tu cuenta'
                                    : 'Bienvenido a Finora',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: FinoraColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: FinoraTokens.s8),
                              const Text(
                                'Tu dinero, bajo control',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: FinoraColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: FinoraTokens.s32),
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Correo electrónico',
                                ),
                              ),
                              const SizedBox(height: FinoraTokens.s16),
                              TextField(
                                controller: _password,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Contraseña',
                                ),
                              ),
                              const SizedBox(height: FinoraTokens.s24),
                              SizedBox(
                                height: 56,
                                child: FilledButton(
                                  onPressed: _loading ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: FinoraColors.primary,
                                    foregroundColor: FinoraColors.surface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        FinoraTokens.rPill,
                                      ),
                                    ),
                                  ),
                                  child: _loading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: FinoraColors.surface,
                                          ),
                                        )
                                      : Text(primaryLabel),
                                ),
                              ),
                              const SizedBox(height: FinoraTokens.s8),
                              TextButton(
                                onPressed: () => setState(
                                  () => _isRegister = !_isRegister,
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: FinoraColors.primary,
                                  minimumSize: const Size(0, 44),
                                ),
                                child: Text(toggleLabel),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo de marca sobre el degradado, envuelto en un contenedor blanco (el
/// asset `logo_inicio` tiene fondo claro y necesita contraste sobre el verde).
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FinoraTokens.s12),
      decoration: BoxDecoration(
        color: FinoraColors.surface,
        borderRadius: BorderRadius.circular(FinoraTokens.rCard),
      ),
      child: Semantics(
        label: 'Finora',
        image: true,
        child: Image.asset('assets/brand/logo_inicio.png', height: 120),
      ),
    );
  }
}
