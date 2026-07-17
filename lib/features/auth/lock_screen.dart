import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/biometric_service.dart';

final biometricServiceProvider = Provider((_) => BiometricService());
final appLockedProvider = StateProvider<bool>((_) => true);

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
    if (ok) ref.read(appLockedProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/brand/logo.png', height: 96),
            const SizedBox(height: 32),
            const Icon(Icons.fingerprint, size: 64),
            const SizedBox(height: 16),
            const Text('Toca el sensor para desbloquear'),
            const SizedBox(height: 24),
            Center(
              child: FilledButton.icon(
                onPressed: _tryUnlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Usar huella'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
