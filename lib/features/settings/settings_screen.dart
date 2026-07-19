import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/finora_colors.dart';
import '../../core/finora_tokens.dart';
import '../../core/finora_widgets.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import '../../services/notifications_service.dart';
import '../auth/auth_providers.dart';
import '../auth/auth_repository.dart';
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

/// Alias del usuario para saludos y cabeceras: el metadato `alias` si el
/// usuario lo configuro (Perfil > lapiz junto al nombre), o la parte local
/// del email como valor inicial. Observa [authStateProvider] para
/// recalcularse cuando llega el evento `userUpdated` tras editar el alias.
/// Mismo criterio de try/catch que [currentUserIdProvider] para los tests.
final currentUserAliasProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final alias = user.userMetadata?['alias'];
    if (alias is String && alias.trim().isNotEmpty) return alias.trim();
    return user.email?.split('@').first;
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
  (ref) =>
      () => ref.read(authRepositoryProvider).signOut(),
);

/// Misma indireccion que [signOutProvider] pero para `SyncCoordinator.trigger`:
/// `syncCoordinatorProvider` toca `Supabase.instance` y `connectivity_plus` en
/// su constructor (ver nota en `sync_providers.dart`), asi que los tests de
/// esta pantalla sobreescriben este provider en vez de forzar esa
/// construccion.
final syncTriggerProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(syncCoordinatorProvider).trigger(),
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
    final row = userId == null
        ? null
        : await ref.read(databaseProvider).settingsDao.get(userId);
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = row?.biometricEnabled ?? false;
      _monthlyLimitCents = row?.monthlyLimitCents;
      _alertDaysBeforeDue = row?.alertDaysBeforeDue ?? 3;
      _limitCtrl.text = _monthlyLimitCents == null
          ? ''
          : (_monthlyLimitCents! / 100).toStringAsFixed(2);
      _loading = false;
    });
  }

  /// Envia siempre la fila completa: `SettingsDao.upsert` usa
  /// `insertOnConflictUpdate`, que valida columnas NOT NULL como si fuera un
  /// INSERT nuevo aunque la fila ya exista (leccion T16/T19).
  Future<void> _persist() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    await ref
        .read(databaseProvider)
        .settingsDao
        .upsert(
          UserSettingsCompanion(
            id: Value(userId),
            monthlyLimitCents: Value(_monthlyLimitCents),
            alertDaysBeforeDue: Value(_alertDaysBeforeDue),
            biometricEnabled: Value(_biometricEnabled),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Monto inválido')));
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
    final next = (_alertDaysBeforeDue + delta).clamp(
      _minAlertDays,
      _maxAlertDays,
    );
    if (next == _alertDaysBeforeDue) return;
    setState(() => _alertDaysBeforeDue = next);
    _persist();
    // Reprograma recordatorios de pago (Task 22) con el nuevo valor de
    // `alertDaysBeforeDue`, mismo patron que `EditAccountSheet._save()`:
    // antes de este fix, un cambio aqui solo se reflejaba en las
    // notificaciones tras el siguiente sync ONLINE exitoso
    // (`SyncCoordinator.trigger()`), lo que es asimetrico con
    // `edit_account_sheet.dart` (reprograma de inmediato al guardar una
    // cuenta) y deja al usuario sin recordatorio actualizado si esta
    // offline o el sync tarda. Best-effort (su propio try/catch): un fallo
    // no debe afectar el guardado del valor, que ya ocurrio arriba.
    rescheduleCardRemindersFromDb(
      ref.read(databaseProvider),
      ref.read(notificationsServiceProvider),
    );
  }

  /// Abre el dialogo de cambio de contraseña (nueva + confirmacion). El
  /// cambio no necesita correo: la sesion vigente autoriza `updateUser`.
  Future<void> _changePassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ChangePasswordDialog(auth: ref.read(authRepositoryProvider)),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Contraseña actualizada')));
    }
  }

  /// Abre el dialogo de edicion del alias y lo persiste en los metadatos de
  /// auth ([AuthRepository.updateAlias]). Requiere conexion (es una llamada a
  /// Supabase): si falla se informa con un snackbar y no se pierde nada.
  Future<void> _editAlias() async {
    final current = ref.read(currentUserAliasProvider) ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _AliasDialog(initial: current),
    );
    if (result == null || result.trim().isEmpty || result.trim() == current) {
      return;
    }
    try {
      await ref.read(authRepositoryProvider).updateAlias(result.trim());
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar el alias. Revisa tu conexión.'),
          ),
        );
      }
    }
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
            child: const Text(
              'Cerrar sesión',
              style: TextStyle(color: FinoraColors.expense),
            ),
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
    final alias = ref.watch(currentUserAliasProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    return Scaffold(
      backgroundColor: FinoraColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Cabecera compacta de marca: avatar con inicial, email y
                  // chip de estado de sincronizacion.
                  BrandHeader(
                    padding: EdgeInsets.zero,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          FinoraTokens.s16,
                          FinoraTokens.s16,
                          FinoraTokens.s16,
                          FinoraTokens.s32,
                        ),
                        child: _Header(
                          alias: alias,
                          email: email,
                          status: syncStatus,
                          onRetry: () => ref.read(syncTriggerProvider)(),
                          onEditAlias: _editAlias,
                        ),
                      ),
                    ),
                  ),
                  // La sheet solapa el header subiendo el radio de sus esquinas.
                  Transform.translate(
                    offset: const Offset(0, -FinoraTokens.rSheet),
                    child: ContentSheet(
                      padding: const EdgeInsets.fromLTRB(
                        FinoraTokens.s16,
                        FinoraTokens.s24,
                        FinoraTokens.s16,
                        FinoraTokens.s24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _GroupTitle('Seguridad'),
                          _GroupCard(
                            children: [
                              if (_biometricAvailable)
                                SwitchListTile(
                                  secondary: const _TileIcon(
                                    Icons.fingerprint,
                                    FinoraColors.primary,
                                  ),
                                  title: const Text('Desbloqueo con huella'),
                                  value: _biometricEnabled,
                                  onChanged: _onBiometricChanged,
                                ),
                              ListTile(
                                leading: const _TileIcon(
                                  Icons.lock_outline,
                                  FinoraColors.primary,
                                ),
                                title: const Text('Cambiar contraseña'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _changePassword,
                              ),
                            ],
                          ),
                          const SizedBox(height: FinoraTokens.s24),
                          const _GroupTitle('Alertas'),
                          _GroupCard(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  FinoraTokens.s16,
                                  FinoraTokens.s16,
                                  FinoraTokens.s16,
                                  FinoraTokens.s8,
                                ),
                                child: TextField(
                                  controller: _limitCtrl,
                                  focusNode: _limitFocus,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onSubmitted: (_) => _commitLimit(),
                                  decoration: const InputDecoration(
                                    labelText: 'Límite de gasto mensual',
                                    helperText:
                                        'Déjalo vacío para no tener límite',
                                    prefixText: 'S/ ',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              ListTile(
                                leading: const _TileIcon(
                                  Icons.notifications_active_outlined,
                                  FinoraColors.warning,
                                ),
                                title: const Text(
                                  'Avisarme antes del vencimiento',
                                ),
                                subtitle: Text(
                                  '$_alertDaysBeforeDue días antes',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      tooltip: 'Menos días',
                                      onPressed:
                                          _alertDaysBeforeDue > _minAlertDays
                                          ? () => _changeAlertDays(-1)
                                          : null,
                                    ),
                                    Text('$_alertDaysBeforeDue'),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                      tooltip: 'Más días',
                                      onPressed:
                                          _alertDaysBeforeDue < _maxAlertDays
                                          ? () => _changeAlertDays(1)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: FinoraTokens.s24),
                          const _GroupTitle('Datos'),
                          _GroupCard(
                            children: [
                              ListTile(
                                leading: const _TileIcon(
                                  Icons.sync,
                                  FinoraColors.savings,
                                ),
                                title: const Text('Sincronizar ahora'),
                                onTap: () => ref.read(syncTriggerProvider)(),
                              ),
                              ListTile(
                                leading: const _TileIcon(
                                  Icons.savings_rounded,
                                  FinoraColors.savings,
                                ),
                                title: const Text('Metas de ahorro'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/goals'),
                              ),
                              ListTile(
                                leading: const _TileIcon(
                                  Icons.calendar_today_outlined,
                                  FinoraColors.savings,
                                ),
                                title: const Text('Calendario'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/calendar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: FinoraTokens.s24),
                          const _GroupTitle('Sesión'),
                          _GroupCard(
                            children: [
                              ListTile(
                                leading: const _TileIcon(
                                  Icons.logout,
                                  FinoraColors.expense,
                                ),
                                title: const Text(
                                  'Cerrar sesión',
                                  style: TextStyle(color: FinoraColors.expense),
                                ),
                                onTap: _confirmSignOut,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Titulo de grupo de ajustes: 12 bold en mayusculas, textSecondary.
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: FinoraTokens.s4,
        bottom: FinoraTokens.s8,
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: FinoraColors.textSecondary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Card unica que agrupa los `ListTile`s de una seccion, con divisores
/// internos entre cada uno (radio [FinoraTokens.rCard]).
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1));
      rows.add(children[i]);
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FinoraTokens.rCard),
      ),
      child: Column(children: rows),
    );
  }
}

/// Icono de tile en un squircle 36 con fondo al 15% del color de dominio.
class _TileIcon extends StatelessWidget {
  const _TileIcon(this.icon, this.color);
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.15),
          FinoraColors.surface,
        ),
        borderRadius: BorderRadius.circular(FinoraTokens.rInput),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// Header compacto: avatar con la inicial del alias (sobre blanco20), alias
/// con lapiz para editarlo, email debajo y estado de sincronizacion como
/// chip. En estado `error` el chip es tocable y reintenta
/// (`SyncCoordinator.trigger`).
class _Header extends StatelessWidget {
  const _Header({
    required this.alias,
    required this.email,
    required this.status,
    required this.onRetry,
    required this.onEditAlias,
  });
  final String? alias;
  final String? email;
  final SyncStatus status;
  final VoidCallback onRetry;
  final VoidCallback onEditAlias;

  @override
  Widget build(BuildContext context) {
    final display = (alias != null && alias!.isNotEmpty) ? alias! : email;
    final initial = (display != null && display.isNotEmpty)
        ? display[0].toUpperCase()
        : '?';
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: FinoraTokens.s16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      display ?? 'Sin sesión',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    tooltip: 'Editar alias',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEditAlias,
                  ),
                ],
              ),
              if (email != null && email != display)
                Text(
                  email!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: FinoraTokens.s8),
              _SyncStatusChip(status: status, onRetry: onRetry),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dialogo "Cambiar contraseña": nueva contraseña + confirmacion (ambas con
/// ojito), valida minimo 6 caracteres y coincidencia, y llama a
/// [AuthRepository.updatePassword]. `StatefulWidget` propio para que los
/// controllers vivan y mueran con el dialogo (misma leccion que `_NoteDialog`
/// en `add_transaction_screen.dart`). Hace pop con `true` solo si el cambio
/// se aplico.
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.auth});
  final AuthRepository auth;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _busy = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final password = _passwordCtrl.text;
    if (password.length < 6) {
      _showError('La contraseña debe tener al menos 6 caracteres');
      return;
    }
    if (password != _confirmCtrl.text) {
      _showError('Las contraseñas no coinciden');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.auth.updatePassword(password);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } on Object {
      if (mounted) {
        _showError('No se pudo cambiar la contraseña. Revisa tu conexión.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _suffixEye(bool obscure, VoidCallback onTap) => IconButton(
    icon: Icon(
      obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      color: FinoraColors.textSecondary,
    ),
    onPressed: onTap,
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _passwordCtrl,
            autofocus: true,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Nueva contraseña',
              suffixIcon: _suffixEye(
                _obscurePassword,
                () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: FinoraTokens.s16),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirmar contraseña',
              suffixIcon: _suffixEye(
                _obscureConfirm,
                () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Dialogo de edicion del alias. `StatefulWidget` propio para que el
/// `TextEditingController` viva y muera con el dialogo (disponer un
/// controller mientras la ruta todavia anima su cierre congela la UI, misma
/// leccion que el dialogo de nota en `add_transaction_screen.dart`).
class _AliasDialog extends StatefulWidget {
  const _AliasDialog({required this.initial});
  final String initial;

  @override
  State<_AliasDialog> createState() => _AliasDialogState();
}

class _AliasDialogState extends State<_AliasDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar alias'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 40,
        decoration: const InputDecoration(
          labelText: 'Alias',
          helperText: 'Así te saludará la app',
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Chip pill (blanco20) con un dot de estado y la etiqueta de sincronizacion:
/// verde=Sincronizado, ambar=Sincronizando, gris=Sin conexion, rojo=Error
/// (tocable para reintentar).
class _SyncStatusChip extends StatelessWidget {
  const _SyncStatusChip({required this.status, required this.onRetry});
  final SyncStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (dotColor, label) = switch (status) {
      SyncStatus.idle => (FinoraColors.income, 'Sincronizado'),
      SyncStatus.syncing => (FinoraColors.warning, 'Sincronizando…'),
      SyncStatus.offline => (FinoraColors.neutral, 'Sin conexión'),
      SyncStatus.error => (
        FinoraColors.expense,
        'Error — toca para reintentar',
      ),
    };
    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FinoraTokens.s12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(FinoraTokens.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: FinoraTokens.s8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (status != SyncStatus.error) return chip;
    return GestureDetector(onTap: onRetry, child: chip);
  }
}
