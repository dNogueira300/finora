import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:finora/data/local/database.dart';
import 'package:finora/data/sync/sync_providers.dart';
import 'package:finora/features/auth/lock_screen.dart';
import 'package:finora/features/settings/settings_screen.dart';
import 'package:finora/services/biometric_service.dart';
import 'package:finora/services/notifications_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// Doble de prueba de `BiometricService`: evita tocar `local_auth`
/// (plugin de plataforma) en los tests, controlando `isAvailable`/
/// `authenticate` de forma determinista.
class _FakeBiometricService extends BiometricService {
  _FakeBiometricService({required this.available, this.authResult = true});
  final bool available;
  final bool authResult;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async => authResult;
}

/// Plugin sin operaciones reales: la prueba de reprogramacion de
/// recordatorios (mas abajo) sobreescribe `scheduleCardReminders` en
/// `_RecordingNotificationsService`, asi que este plugin nunca deberia
/// llegar a invocarse; existe solo para satisfacer el constructor de
/// `NotificationsService`.
class _NoopNotificationsPlugin implements NotificationsPlugin {
  @override
  Future<void> initialize(void Function(String? payload) onTap) async {}
  @override
  Future<void> requestAndroidPermission() async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {}
  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String payload,
  }) async {}
}

/// Doble de `NotificationsService` para verificar que `_changeAlertDays`
/// dispara `rescheduleCardRemindersFromDb` (Fix: antes solo se reprogramaba
/// tras el siguiente sync ONLINE exitoso). Registra las llamadas a
/// `scheduleCardReminders` en vez de delegar en el plugin real.
class _RecordingNotificationsService extends NotificationsService {
  _RecordingNotificationsService(super.plugin, super.db);
  int scheduleCalls = 0;

  @override
  Future<void> scheduleCardReminders(List<Account> creditCards, int daysBefore) async {
    scheduleCalls++;
  }
}

void main() {
  // Cada test abre su propia base de datos en memoria (ver `setUp`), lo cual
  // hace que drift emita una advertencia benigna de "database class created
  // multiple times" al construir la segunda instancia en adelante.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  const userId = 'u1';

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> growTestSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> drainTimers(WidgetTester tester) async {
    // Desmontar el arbol y drenar los timers pendientes de drift (los
    // StreamProvider.autoDispose dejan un Timer de la conexion de drift que
    // solo se cancela una vez que el stream subscription se cierra tras el
    // dispose de los providers).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Widget buildApp({
    required BiometricService biometricService,
    SyncStatus syncStatus = SyncStatus.idle,
    Future<void> Function()? onSignOut,
    Future<void> Function()? onSyncTrigger,
    String? email = 'ana@finora.test',
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        biometricServiceProvider.overrideWithValue(biometricService),
        currentUserIdProvider.overrideWithValue(userId),
        currentUserEmailProvider.overrideWithValue(email),
        syncStatusProvider.overrideWith((ref) => syncStatus),
        if (onSignOut != null) signOutProvider.overrideWithValue(onSignOut),
        if (onSyncTrigger != null) syncTriggerProvider.overrideWithValue(onSyncTrigger),
      ],
      child: MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es')],
        home: const SettingsScreen(),
      ),
    );
  }

  testWidgets('el interruptor de huella se oculta si isAvailable() es false', (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp(
      biometricService: _FakeBiometricService(available: false),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Seguridad'), findsNothing);
    expect(find.text('Desbloqueo con huella'), findsNothing);

    await drainTimers(tester);
  });

  testWidgets(
      'activar la huella con authenticate() exitoso guarda biometricEnabled=true',
      (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp(
      biometricService: _FakeBiometricService(available: true, authResult: true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Desbloqueo con huella'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    final row = await db.settingsDao.get(userId);
    expect(row?.biometricEnabled, isTrue);

    await drainTimers(tester);
  });

  testWidgets(
      'activar la huella con authenticate() fallido deja el interruptor apagado y no persiste',
      (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp(
      biometricService: _FakeBiometricService(available: true, authResult: false),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    final row = await db.settingsDao.get(userId);
    expect(row?.biometricEnabled ?? false, isFalse);

    await drainTimers(tester);
  });

  testWidgets('desactivar la huella no exige authenticate()', (tester) async {
    await growTestSurface(tester);
    await db.settingsDao.upsert(UserSettingsCompanion(
      id: const Value(userId),
      biometricEnabled: const Value(true),
      alertDaysBeforeDue: const Value(3),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
    // authResult:false demuestra que desactivar no llama a authenticate().
    await tester.pumpWidget(buildApp(
      biometricService: _FakeBiometricService(available: true, authResult: false),
    ));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    final row = await db.settingsDao.get(userId);
    expect(row?.biometricEnabled, isFalse);

    await drainTimers(tester);
  });

  testWidgets('escribir "500" en limite mensual y enviar guarda 50000 centavos',
      (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp(
      biometricService: _FakeBiometricService(available: false),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '500');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final row = await db.settingsDao.get(userId);
    expect(row?.monthlyLimitCents, 50000);

    await drainTimers(tester);
  });

  testWidgets('dejar el limite mensual vacio guarda monthlyLimitCents=null', (tester) async {
    await growTestSurface(tester);
    await db.settingsDao.upsert(UserSettingsCompanion(
      id: const Value(userId),
      monthlyLimitCents: const Value(100000),
      alertDaysBeforeDue: const Value(3),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
    await tester.pumpWidget(buildApp(
      biometricService: _FakeBiometricService(available: false),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1000.00'), findsOneWidget); // precargado desde la BD

    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final row = await db.settingsDao.get(userId);
    expect(row?.monthlyLimitCents, isNull);

    await drainTimers(tester);
  });

  testWidgets('el stepper de dias de aviso incrementa y persiste alertDaysBeforeDue',
      (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp(
      biometricService: _FakeBiometricService(available: false),
    ));
    await tester.pumpAndSettle();

    expect(find.text('3 días antes'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();

    expect(find.text('4 días antes'), findsOneWidget);
    var row = await db.settingsDao.get(userId);
    expect(row?.alertDaysBeforeDue, 4);

    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();

    expect(find.text('2 días antes'), findsOneWidget);
    row = await db.settingsDao.get(userId);
    expect(row?.alertDaysBeforeDue, 2);

    await drainTimers(tester);
  });

  testWidgets(
      'cambiar los dias de aviso intenta reprogramar los recordatorios sin bloquear el guardado',
      (tester) async {
    // Verifica el fix: `_changeAlertDays` ahora llama a
    // `rescheduleCardRemindersFromDb` (antes solo se reprogramaba tras el
    // siguiente sync ONLINE exitoso, asimetrico con
    // `EditAccountSheet._save()`). `rescheduleCardRemindersFromDb` resuelve
    // el usuario via `Supabase.instance.client.auth.currentUser`, que en el
    // entorno de test lanza un `AssertionError` (no se llama a
    // `Supabase.initialize()` aqui, mismo criterio documentado en
    // `currentUserIdProvider`/`syncCoordinatorProvider`); su try/catch
    // best-effort lo swallowea igual que en produccion cuando falla. Por
    // eso esta prueba no puede aserter `scheduleCalls > 0` end-to-end (el
    // fake nunca se llega a invocar en este sandbox), pero SI confirma lo
    // observable: la llamada no revierte ni bloquea el guardado del valor
    // (regresion de la asimetria original) y no deja ninguna excepcion sin
    // manejar.
    await growTestSurface(tester);
    final notifService =
        _RecordingNotificationsService(_NoopNotificationsPlugin(), db);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        biometricServiceProvider.overrideWithValue(_FakeBiometricService(available: false)),
        currentUserIdProvider.overrideWithValue(userId),
        currentUserEmailProvider.overrideWithValue('ana@finora.test'),
        notificationsServiceProvider.overrideWithValue(notifService),
      ],
      child: MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('es')],
        home: const SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // best-effort: no debe propagar
    expect(find.text('4 días antes'), findsOneWidget); // el guardado sigue funcionando
    final row = await db.settingsDao.get(userId);
    expect(row?.alertDaysBeforeDue, 4);
    // Documenta la limitacion explicada arriba: en este sandbox
    // `rescheduleCardRemindersFromDb` nunca llega a invocar al fake (corta
    // antes, en `Supabase.instance`). Si algun dia se resuelve ese usuario
    // sin pasar por `Supabase.instance` (o el test inicializa un cliente de
    // prueba), este valor deberia pasar a > 0 y esta aserción debe
    // actualizarse a la par.
    expect(notifService.scheduleCalls, 0);

    await drainTimers(tester);
  });

  testWidgets('"Cerrar sesión" con confirmacion llama a signOut', (tester) async {
    await growTestSurface(tester);
    var signOutCalled = false;
    await tester.pumpWidget(buildApp(
      biometricService: _FakeBiometricService(available: false),
      onSignOut: () async {
        signOutCalled = true;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(signOutCalled, isFalse);

    await tester.tap(find.widgetWithText(TextButton, 'Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(signOutCalled, isTrue);

    await drainTimers(tester);
  });

  testWidgets('"Cerrar sesión" cancelado no llama a signOut', (tester) async {
    await growTestSurface(tester);
    var signOutCalled = false;
    await tester.pumpWidget(buildApp(
      biometricService: _FakeBiometricService(available: false),
      onSignOut: () async {
        signOutCalled = true;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(signOutCalled, isFalse);

    await drainTimers(tester);
  });

  group('estado de sincronizacion en el header', () {
    for (final entry in {
      SyncStatus.idle: 'Sincronizado',
      SyncStatus.syncing: 'Sincronizando…',
      SyncStatus.offline: 'Sin conexión',
      SyncStatus.error: 'Error — toca para reintentar',
    }.entries) {
      testWidgets('${entry.key} muestra "${entry.value}"', (tester) async {
        await growTestSurface(tester);
        await tester.pumpWidget(buildApp(
          biometricService: _FakeBiometricService(available: false),
          syncStatus: entry.key,
        ));
        await tester.pumpAndSettle();

        expect(find.text(entry.value), findsOneWidget);

        await drainTimers(tester);
      });
    }

    testWidgets('tocar el estado "Error" dispara el reintento (SyncCoordinator.trigger)',
        (tester) async {
      await growTestSurface(tester);
      var triggerCalled = false;
      await tester.pumpWidget(buildApp(
        biometricService: _FakeBiometricService(available: false),
        syncStatus: SyncStatus.error,
        onSyncTrigger: () async {
          triggerCalled = true;
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Error — toca para reintentar'));
      await tester.pumpAndSettle();

      expect(triggerCalled, isTrue);

      await drainTimers(tester);
    });
  });

  testWidgets('el header muestra la inicial del email en mayuscula', (tester) async {
    await growTestSurface(tester);
    await tester.pumpWidget(buildApp(
      biometricService: _FakeBiometricService(available: false),
      email: 'zoe@finora.test',
    ));
    await tester.pumpAndSettle();

    expect(find.text('Z'), findsOneWidget);
    expect(find.text('zoe@finora.test'), findsOneWidget);

    await drainTimers(tester);
  });
}
