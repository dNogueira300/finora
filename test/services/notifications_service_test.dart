// Reemplaza el "Step 4: Prueba manual" del brief de Task 22 por pruebas
// automatizadas: un fake de `NotificationsPlugin` (el seam entre el
// servicio y `flutter_local_notifications`, ver `notifications_service.dart`)
// para verificar los parametros exactos de `scheduleCardReminders`, y una
// base de datos en memoria real para verificar que `showNow` inserta la
// alerta (Task 20) con un titulo alineado a la heuristica de icono de
// `AlertsScreen` ("pago"/"vencimiento"/"cierre" -> tarjeta azul).
//
// La verificacion en dispositivo real (permiso POST_NOTIFICATIONS,
// notificacion mostrada por Android, `pendingNotificationRequests()`) queda
// pendiente: no se puede automatizar sin un emulador/dispositivo.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:finora/data/local/database.dart';
import 'package:finora/services/notifications_service.dart';

/// Fake de `NotificationsPlugin`: registra cada llamada (orden incluido) en
/// vez de tocar platform channels, para poder aserter los parametros exactos
/// que `NotificationsService` calcula (id, titulo, cuerpo, `TZDateTime`).
class FakeNotificationsPlugin implements NotificationsPlugin {
  final List<String> calls = [];
  final List<({int id, String title, String body, tz.TZDateTime scheduledDate})> scheduled = [];
  final List<({int id, String title, String body})> shown = [];
  void Function(String? payload)? onTap;

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    this.onTap = onTap;
    calls.add('initialize');
  }

  @override
  Future<void> requestAndroidPermission() async {
    calls.add('requestAndroidPermission');
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    calls.add('show:$id');
    shown.add((id: id, title: title, body: body));
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String payload,
  }) async {
    calls.add('zonedSchedule:$id');
    scheduled.add((id: id, title: title, body: body, scheduledDate: scheduledDate));
  }
}

Account _creditAccount(String id, {int? paymentDueDay}) => Account(
      id: id,
      updatedAt: DateTime.utc(2026, 1, 1),
      isDirty: false,
      name: 'Tarjeta $id',
      type: 'credit',
      initialBalanceCents: 0,
      color: 0xFF000000,
      isArchived: false,
      paymentDueDay: paymentDueDay,
    );

void main() {
  // Sincrono: se necesita ANTES de calcular `limaLocation` mas abajo, que se
  // evalua al construir el `main()` (antes de que corra ningun `setUpAll`).
  tz_data.initializeTimeZones();

  // "Hoy" fijo para todas las pruebas: 2026-07-17 00:00 hora de Lima
  // (05:00 UTC, Lima es UTC-5 fijo). Coincide con la fecha "actual" usada en
  // el resto de la suite/documentacion de esta tarea.
  final fixedNowUtc = DateTime.utc(2026, 7, 17, 5);
  final limaLocation = tz.getLocation('America/Lima');

  group('scheduleCardReminders', () {
    late FakeNotificationsPlugin plugin;
    late AppDatabase db;
    late NotificationsService service;

    setUp(() {
      plugin = FakeNotificationsPlugin();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = NotificationsService(plugin, db, nowUtc: () => fixedNowUtc);
    });

    tearDown(() => db.close());

    test('cancela lo programado antes de agendar', () async {
      await service.scheduleCardReminders([_creditAccount('a1', paymentDueDay: 20)], 3);
      expect(plugin.calls.first, 'cancelAll');
      expect(plugin.calls.indexOf('cancelAll'), lessThan(plugin.calls.indexOf('zonedSchedule:${'a1'.hashCode & 0x7fffffff}')));
    });

    test('agenda a las 9am de Lima, N dias antes de la proxima fecha de vencimiento', () async {
      // dueDay=20: nextDueDate(20, 2026-07-17) = 2026-07-20 (no paso aun).
      // reminderDateTime(2026-07-20, 3) = 2026-07-17 09:00 (mismo dia, en el
      // futuro respecto a las 00:00 de "hoy" fijado arriba).
      final card = _creditAccount('a1', paymentDueDay: 20);
      await service.scheduleCardReminders([card], 3);

      expect(plugin.scheduled, hasLength(1));
      final req = plugin.scheduled.single;
      expect(req.id, 'a1'.hashCode & 0x7fffffff);
      expect(req.scheduledDate, tz.TZDateTime(limaLocation, 2026, 7, 17, 9));
      expect(req.title.toLowerCase(), contains('pago')); // alineado a la heuristica de icono de AlertsScreen
      expect(req.body, contains('Tarjeta a1'));
      expect(req.body, contains('20/07/2026'));
    });

    test('omite tarjetas con paymentDueDay nulo', () async {
      await service.scheduleCardReminders([_creditAccount('a1', paymentDueDay: null)], 3);
      expect(plugin.scheduled, isEmpty);
    });

    test('omite el recordatorio si la fecha resultante ya paso (vencimiento manana, 3 dias antes)',
        () async {
      // dueDay=18: nextDueDate(18, 2026-07-17) = 2026-07-18 (manana).
      // reminderDateTime(2026-07-18, 3) = 2026-07-15 09:00, que ya paso
      // respecto a "hoy" (2026-07-17 00:00 Lima): no debe agendarse
      // (zonedSchedule lanzaria si se agenda en el pasado).
      await service.scheduleCardReminders([_creditAccount('a1', paymentDueDay: 18)], 3);
      expect(plugin.scheduled, isEmpty);
    });

    test('agenda una notificacion por cada tarjeta elegible, con ids estables y distintos',
        () async {
      final cards = [
        _creditAccount('a1', paymentDueDay: 20),
        _creditAccount('a2', paymentDueDay: 25),
        _creditAccount('a3', paymentDueDay: null), // omitida
      ];
      await service.scheduleCardReminders(cards, 3);

      expect(plugin.scheduled, hasLength(2));
      final ids = plugin.scheduled.map((r) => r.id).toSet();
      expect(ids, {'a1'.hashCode & 0x7fffffff, 'a2'.hashCode & 0x7fffffff});
      expect(ids, everyElement(greaterThanOrEqualTo(0))); // & 0x7fffffff siempre no-negativo

      // Volver a llamar con la misma tarjeta produce el mismo id (estable).
      plugin.scheduled.clear();
      await service.scheduleCardReminders([cards[0]], 3);
      expect(plugin.scheduled.single.id, 'a1'.hashCode & 0x7fffffff);
    });
  });

  group('init / tocar una notificacion programada', () {
    test(
        'init registra onDidReceiveNotificationResponse; tocar la notificacion inserta la alerta',
        () async {
      final plugin = FakeNotificationsPlugin();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final service = NotificationsService(plugin, db, nowUtc: () => fixedNowUtc);

      await service.init();
      expect(plugin.calls, ['initialize', 'requestAndroidPermission']);
      expect(plugin.onTap, isNotNull);

      // Simula el tap: el plugin real invocaria esto desde
      // `onDidReceiveNotificationResponse` con el payload de la notificacion
      // (ver `PluginNotificationsAdapter.initialize`). Insertar en el
      // momento del tap (no al disparar) es la resolucion documentada para
      // notificaciones PROGRAMADAS, ver comentario de clase de
      // `NotificationsService`.
      plugin.onTap!('{"title":"Pago de tarjeta próximo","body":"Tu pago de Visa Oro vence el 20/07/2026."}');
      await Future<void>.delayed(Duration.zero); // insertAlert es fire-and-forget (unawaited)

      final alerts = await db.select(db.localAlerts).get();
      expect(alerts, hasLength(1));
      expect(alerts.single.title, 'Pago de tarjeta próximo');
    });

    test('tocar con payload nulo o invalido no inserta nada ni lanza', () async {
      final plugin = FakeNotificationsPlugin();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final service = NotificationsService(plugin, db, nowUtc: () => fixedNowUtc);

      await service.init();
      plugin.onTap!(null);
      plugin.onTap!('no es json');
      await Future<void>.delayed(Duration.zero);

      expect(await db.select(db.localAlerts).get(), isEmpty);
    });
  });

  group('showNow', () {
    test('inserta la alerta en LocalAlerts de inmediato con un titulo que activa el icono de tarjeta',
        () async {
      final plugin = FakeNotificationsPlugin();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final service = NotificationsService(plugin, db, nowUtc: () => fixedNowUtc);

      await service.showNow('Pago de tarjeta próximo', 'Tu pago de Visa Oro vence el 20/07/2026.');

      expect(plugin.shown, hasLength(1));
      expect(plugin.shown.single.title, 'Pago de tarjeta próximo');

      final alerts = await db.select(db.localAlerts).get();
      expect(alerts, hasLength(1));
      expect(alerts.single.title, 'Pago de tarjeta próximo');
      expect(alerts.single.body, 'Tu pago de Visa Oro vence el 20/07/2026.');
      expect(alerts.single.isRead, isFalse);
      // Heuristica de icono de AlertsScreen (alerts_screen.dart, `_alertIcon`):
      // "pago" -> icono de tarjeta azul.
      expect(alerts.single.title.toLowerCase(), contains('pago'));
    });
  });
}
