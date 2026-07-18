import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/finora_colors.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import '../auth/auth_providers.dart';
import '../auth/lock_screen.dart';

/// Id del usuario autenticado, o null si no hay sesion. Mismo criterio que
/// `_currentUserEmail` en `dashboard_screen.dart`: en tests de widgets no se
/// llama a `Supabase.initialize()` y `Supabase.instance` lanza un
/// `AssertionError`, que aqui se trata igual que "sin sesion". Publico (sin
/// `_`) para poder fijarlo con un id de prueba fijo en los tests de esta
/// pantalla.
final currentUserIdProvider = Provider<String?>((ref) {
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } on Object {
    return null;
  }
});

/// Email del usuario autenticado, mismo criterio que [currentUserIdProvider].
final currentUserEmailProvider = Provider<String?>((ref) {
  try {
    return Supabase.instance.client.auth.currentUser?.email;
  } on Object {
    return null;
  }
});

/// Indireccion sobre `AuthRepository.signOut` para poder testear el flujo de
/// "Cerrar sesión" sin construir un `SupabaseClient` real (lo que exigiria
/// `Supabase.initialize()` en el test). En produccion delega directamente en
/// `authRepositoryProvider`; el redirect a `/login` lo maneja el router
/// (Task 10), esta pantalla no navega manualmente.
final signOutProvider = Provider<Future<void> Function()>(
  (ref) => () => ref.read(authRepositoryProvider).signOut(),
);

/// Misma indireccion que [signOutProvider] pero para `SyncCoordinator.trigger`:
/// `syncCoordinatorProvider` toca `Supabase.instance` y `connectivity_plus` en
/// su constructor (ver nota en `sync_providers.dart`), asi que los tests de
/// esta pantalla sobreescriben este provider en vez de forzar esa
/// construccion.
final syncTriggerProvider = Provider<Future<void> Function()>(
  (ref) => () => ref.read(syncCoordinatorProvider).trigger(),
);

const _minAlertDays = 0;
const _maxAlertDays = 30;

/// Pantalla "Perfil" (Task 21, referencia Stitch "Perfil y Configuración"):
/// header con avatar/email/estado de sync + 4 secciones (Seguridad, Alertas,
/// Datos, Sesión). El interruptor de huella solo se muestra si
/// `BiometricService.isAvailable()`, y activarlo exige `authenticate()`
/// exitoso antes de guardar `biometricEnabled = true` (desactivar no exige
/// nada). El limite mensual y el stepper de dias de aviso se persisten con
/// `SettingsDao.upsert`, siempre enviando la fila completa (ver nota de
/// `_persist`, mismo problema de `insertOnConflictUpdate` que T16/T19).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  int? _monthlyLimitCents;
  int _alertDaysBeforeDue = 3;

  late final TextEditingController _limitCtrl;
  late final FocusNode _limitFocus;

  @override
  void initState() {
    super.initState();
    _limitCtrl = TextEditingController();
    _limitFocus = FocusNode()..addListener(_onLimitFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _limitFocus.removeListener(_onLimitFocusChange);
    _limitFocus.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  void _onLimitFocusChange() {
    if (!_limitFocus.hasFocus) _commitLimit();
  }

  Future<void> _load() async {
    final available = await ref.read(biometricServiceProvider).isAvailable();
    final userId = ref.read(currentUserIdProvider);
    final row =
        userId == null ? null : await ref.read(databaseProvider).settingsDao.get(userId);
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = row?.biometricEnabled ?? false;
      _monthlyLimitCents = row?.monthlyLimitCents;
      _alertDaysBeforeDue = row?.alertDaysBeforeDue ?? 3;
      _limitCtrl.text =
          _monthlyLimitCents == null ? '' : (_monthlyLimitCents! / 100).toStringAsFixed(2);
      _loading = false;
    });
  }

  /// Envia siempre la fila completa: `SettingsDao.upsert` usa
  /// `insertOnConflictUpdate`, que valida columnas NOT NULL como si fuera un
  /// INSERT nuevo aunque la fila ya exista (leccion T16/T19).
  Future<void> _persist() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    await ref.read(databaseProvider).settingsDao.upsert(UserSettingsCompanion(
          id: Value(userId),
          monthlyLimitCents: Value(_monthlyLimitCents),
          alertDaysBeforeDue: Value(_alertDaysBeforeDue),
          biometricEnabled: Value(_biometricEnabled),
          updatedAt: Value(DateTime.now().toUtc()),
        ));
  }

  void _commitLimit() {
    final text = _limitCtrl.text.trim();
    if (text.isEmpty) {
      if (_monthlyLimitCents == null) return;
      setState(() => _monthlyLimitCents = null);
      _persist();
      return;
    }
    final cents = parseMoney(text);
    if (cents == null || cents < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Monto inválido')));
      return;
    }
    if (cents == _monthlyLimitCents) return;
    setState(() => _monthlyLimitCents = cents);
    _persist();
  }

  Future<void> _onBiometricChanged(bool value) async {
    if (value) {
      final ok = await ref.read(biometricServiceProvider).authenticate();
      if (!ok) return; // el interruptor se queda apagado
    }
    setState(() => _biometricEnabled = value);
    await _persist();
  }

  void _changeAlertDays(int delta) {
    final next = (_alertDaysBeforeDue + delta).clamp(_minAlertDays, _maxAlertDays);
    if (next == _alertDaysBeforeDue) return;
    setState(() => _alertDaysBeforeDue = next);
    _persist();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar sesión', style: TextStyle(color: FinoraColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(signOutProvider)();
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(currentUserEmailProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Header(
                    email: email,
                    status: syncStatus,
                    onRetry: () => ref.read(syncTriggerProvider)(),
                  ),
                  const SizedBox(height: 24),
                  if (_biometricAvailable) ...[
                    const _SectionTitle('Seguridad'),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: SwitchListTile(
                        title: const Text('Desbloqueo con huella'),
                        value: _biometricEnabled,
                        onChanged: _onBiometricChanged,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const _SectionTitle('Alertas'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: TextField(
                            controller: _limitCtrl,
                            focusNode: _limitFocus,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onSubmitted: (_) => _commitLimit(),
                            decoration: const InputDecoration(
                              labelText: 'Límite de gasto mensual',
                              helperText: 'Déjalo vacío para no tener límite',
                              prefixText: 'S/ ',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        ListTile(
                          title: const Text('Avisarme antes del vencimiento'),
                          subtitle: Text('$_alertDaysBeforeDue días antes'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                tooltip: 'Menos días',
                                onPressed: _alertDaysBeforeDue > _minAlertDays
                                    ? () => _changeAlertDays(-1)
                                    : null,
                              ),
                              Text('$_alertDaysBeforeDue'),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                tooltip: 'Más días',
                                onPressed: _alertDaysBeforeDue < _maxAlertDays
                                    ? () => _changeAlertDays(1)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('Datos'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.sync, color: FinoraColors.secondary),
                          title: const Text('Sincronizar ahora'),
                          onTap: () => ref.read(syncTriggerProvider)(),
                        ),
                        ListTile(
                          leading: const Icon(Icons.savings_rounded, color: FinoraColors.savings),
                          title: const Text('Metas de ahorro'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go('/goals'),
                        ),
                        ListTile(
                          leading:
                              const Icon(Icons.calendar_today_outlined, color: FinoraColors.primary),
                          title: const Text('Calendario'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/calendar'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('Sesión'),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: const Icon(Icons.logout, color: FinoraColors.expense),
                      title: const Text('Cerrar sesión', style: TextStyle(color: FinoraColors.expense)),
                      onTap: _confirmSignOut,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Header de la pantalla: avatar con la inicial del email, email y estado de
/// sincronizacion. En estado `error` el texto es tocable y reintenta
/// (`SyncCoordinator.trigger`).
class _Header extends StatelessWidget {
  const _Header({required this.email, required this.status, required this.onRetry});
  final String? email;
  final SyncStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final initial = (email != null && email!.isNotEmpty) ? email![0].toUpperCase() : '?';
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: FinoraColors.primary,
          child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 22)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email ?? 'Sin sesión',
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              _SyncStatusLabel(status: status, onRetry: onRetry),
            ],
          ),
        ),
      ],
    );
  }
}

class _SyncStatusLabel extends StatelessWidget {
  const _SyncStatusLabel({required this.status, required this.onRetry});
  final SyncStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      SyncStatus.idle => (Icons.cloud_done, FinoraColors.income, 'Sincronizado'),
      SyncStatus.syncing => (Icons.sync, FinoraColors.secondary, 'Sincronizando…'),
      SyncStatus.offline => (Icons.cloud_off, FinoraColors.textSecondary, 'Sin conexión'),
      SyncStatus.error =>
        (Icons.cloud_off, FinoraColors.expense, 'Error — toca para reintentar'),
    };
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
    if (status != SyncStatus.error) return content;
    return GestureDetector(onTap: onRetry, child: content);
  }
}
