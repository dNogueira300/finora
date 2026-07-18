import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/dates.dart';
import '../data/local/database.dart';
import '../data/sync/sync_providers.dart';
import '../features/alerts/alerts_dao_ext.dart';
import '../features/calendar/due_dates.dart';

/// `tz_data.initializeTimeZones()` es idempotente (solo reconstruye un mapa
/// interno, sin guardar estado de "ya inicializado" que falle en la segunda
/// llamada), asi que no hace falta cachear un booleano: cada punto que
/// necesita `tz.getLocation` simplemente vuelve a llamarla. Ver
/// `NotificationsService.init` y `scheduleCardReminders`.
void _ensureTzInitialized() => tz_data.initializeTimeZones();

/// Fecha/hora del recordatorio de pago: `daysBefore` dias antes de
/// `dueDate`, a las 9:00 am. Funcion pura (sin zona horaria explicita: quien
/// llama la interpreta en America/Lima al construir el `tz.TZDateTime` para
/// `zonedSchedule`, ver `NotificationsService.scheduleCardReminders`).
DateTime reminderDateTime(DateTime dueDate, int daysBefore) =>
    DateTime(dueDate.year, dueDate.month, dueDate.day - daysBefore, 9);

const _channelId = 'finora_reminders';
const _channelName = 'Recordatorios';
const _channelDescription = 'Recordatorios de pago de tarjetas y vencimientos';

/// Codifica titulo+cuerpo en el payload de la notificacion, para poder
/// reconstruirlos en `NotificationsService._onNotificationTap` (registrado
/// como `onDidReceiveNotificationResponse` via `NotificationsPlugin.initialize`)
/// sin depender de una tabla/isolate adicional.
String _payloadFor(String title, String body) => jsonEncode({'title': title, 'body': body});

/// dd/mm/aaaa sin depender de `intl`/locale (evita acoplar el servicio a la
/// inicializacion de formato de fecha, que ya vive en `main.dart`).
String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Seam minimo entre `NotificationsService` y `flutter_local_notifications`:
/// solo los metodos que el servicio necesita. `FlutterLocalNotificationsPlugin`
/// es un singleton con constructor privado (no se puede extender fuera de su
/// libreria para crear un fake), asi que esta interfaz permite inyectar una
/// implementacion falsa en tests sin tocar platform channels.
abstract class NotificationsPlugin {
  /// Inicializa el plugin nativo (canal `finora_reminders` incluido) y
  /// registra `onTap`, invocado con el payload (JSON `{title, body}` o null)
  /// cuando el usuario toca una notificacion.
  Future<void> initialize(void Function(String? payload) onTap);

  /// Pide el permiso POST_NOTIFICATIONS (Android 13+). No-op en versiones
  /// anteriores u otras plataformas.
  Future<void> requestAndroidPermission();

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });

  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String payload,
  });

  Future<void> cancelAll();
}

/// Implementacion real sobre `flutter_local_notifications` 22.x.
class PluginNotificationsAdapter implements NotificationsPlugin {
  PluginNotificationsAdapter(this._plugin);
  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
        ));
  }

  @override
  Future<void> requestAndroidPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // Permiso denegado o no soportado (Android <13, otra plataforma): la
      // app sigue funcionando, Android simplemente no mostrara las
      // notificaciones (Task 22 brief, Step 3).
    }
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) {
    return _plugin.show(
        id: id, title: title, body: body, notificationDetails: _details, payload: payload);
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String payload,
  }) {
    return _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// Servicio de notificaciones locales (Task 22): inicializacion del plugin +
/// canal `finora_reminders`, notificaciones inmediatas (`showNow`) y
/// recordatorios de pago de tarjetas de credito (`scheduleCardReminders`).
///
/// `insertAlert` (Task 20) alinea el titulo de la alerta en pantalla con la
/// heuristica de icono de `AlertsScreen`: los titulos de recordatorio de
/// tarjeta contienen "pago"/"vencimiento" a proposito (icono de tarjeta
/// azul). `showNow` inserta la alerta al instante; para las notificaciones
/// PROGRAMADAS (`scheduleCardReminders`), insertar en el momento exacto en
/// que disparan requeriria un isolate en segundo plano (poco confiable aqui,
/// ver brief) — en su lugar, `initialize` registra `onDidReceiveNotificationResponse`
/// para insertar la alerta cuando el usuario TOCA la notificacion. El
/// historial en pantalla de un recordatorio programado que nunca se toca no
/// aparece en `AlertsScreen` (queda pendiente para Task 23, que ademas hace
/// sus propias verificaciones in-app llamando `insertAlert` directamente).
class NotificationsService {
  NotificationsService(this._plugin, this._db, {DateTime Function()? nowUtc})
      : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final NotificationsPlugin _plugin;
  final AppDatabase _db;
  final DateTime Function() _nowUtc;

  Future<void> init() async {
    _ensureTzInitialized();
    await _plugin.initialize(_onNotificationTap);
    await _plugin.requestAndroidPermission();
  }

  void _onNotificationTap(String? payload) {
    if (payload == null) return;
    try {
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final title = decoded['title'] as String?;
      final body = decoded['body'] as String?;
      if (title != null && body != null) {
        unawaited(_db.insertAlert(title, body));
      }
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // Payload no es el JSON esperado: se ignora (no deberia ocurrir para
      // notificaciones creadas por este servicio).
    }
  }

  /// Muestra una notificacion inmediata e inserta su alerta en el historial
  /// local al instante (a diferencia de las programadas, ver comentario de
  /// clase).
  Future<void> showNow(String title, String body) async {
    final id = _nowUtc().millisecondsSinceEpoch.remainder(0x7fffffff);
    await _plugin.show(id: id, title: title, body: body, payload: _payloadFor(title, body));
    await _db.insertAlert(title, body);
  }

  /// Cancela todos los recordatorios programados (esta app solo programa
  /// recordatorios de pago, asi que `cancelAll` es equivalente y mas simple
  /// que cancelar por id) y agenda uno por cada tarjeta de credito con
  /// `paymentDueDay` no nulo, a las 9:00 am hora de Lima, `daysBefore` dias
  /// antes de su proxima fecha de vencimiento (`nextDueDate`, Task 17). Si
  /// esa fecha/hora ya paso (p. ej. vencimiento manana con `daysBefore` 3),
  /// se omite esa tarjeta: `zonedSchedule` lanza si se agenda en el pasado.
  /// Id estable por tarjeta: `account.id.hashCode & 0x7fffffff`.
  ///
  /// Llama `_ensureTzInitialized()` por su cuenta (no asume que `init()` ya
  /// corrio): depender de ese orden es un invariante no-local que un futuro
  /// llamador podria romper en silencio (el `tz.getLocation` de mas abajo
  /// fallaria dentro del try/catch best-effort de quien invoque este metodo,
  /// sin ninguna señal visible).
  Future<void> scheduleCardReminders(List<Account> creditCards, int daysBefore) async {
    _ensureTzInitialized();
    await _plugin.cancelAll();
    final nowLima = toLima(_nowUtc());
    final todayLima = DateTime(nowLima.year, nowLima.month, nowLima.day);
    final limaLocation = tz.getLocation('America/Lima');

    for (final card in creditCards) {
      final dueDay = card.paymentDueDay;
      if (dueDay == null) continue;

      final dueDate = nextDueDate(dueDay, todayLima);
      final reminder = reminderDateTime(dueDate, daysBefore);
      if (reminder.isBefore(nowLima)) continue;

      final scheduled = tz.TZDateTime(
          limaLocation, reminder.year, reminder.month, reminder.day, reminder.hour);
      const title = 'Pago de tarjeta próximo';
      final body = 'Tu pago de ${card.name} vence el ${_formatDate(dueDate)}.';

      await _plugin.zonedSchedule(
        id: card.id.hashCode & 0x7fffffff,
        title: title,
        body: body,
        scheduledDate: scheduled,
        payload: _payloadFor(title, body),
      );
    }
  }
}

/// Instancia unica de `NotificationsService`, expuesta a `main.dart` (init
/// al arrancar), `SyncCoordinator.trigger()` (reprograma tras cada sync
/// exitoso) y `EditAccountSheet` (reprograma al guardar una cuenta).
final notificationsServiceProvider = Provider<NotificationsService>((ref) {
  final plugin = PluginNotificationsAdapter(FlutterLocalNotificationsPlugin());
  return NotificationsService(plugin, ref.watch(databaseProvider));
});

/// Reprograma los recordatorios de pago a partir del estado actual de la DB:
/// usuario autenticado -> sus settings (`alertDaysBeforeDue`) -> sus cuentas
/// de credito activas -> `NotificationsService.scheduleCardReminders`.
///
/// Punto unico compartido por los dos lugares que reprograman (Task 22):
/// `SyncCoordinator.trigger()` tras un sync exitoso y
/// `EditAccountSheet._save()` tras guardar una cuenta (de cualquier tipo:
/// si una tarjeta se convierte a otro tipo, `scheduleCardReminders` cancela
/// su recordatorio pendiente igual, porque cancela todo antes de reagendar).
///
/// Recibe `db`/`service` en vez de un `Ref`/`WidgetRef` a proposito:
/// `SyncCoordinator` usa `Ref` y `EditAccountSheet` usa `WidgetRef`, que en
/// flutter_riverpod 2.x son interfaces separadas (`WidgetRef` no extiende
/// `Ref`), asi que un parametro unico de tipo `Ref` no serviria para ambos
/// sitios; cada llamador resuelve `databaseProvider`/`notificationsServiceProvider`
/// con su propio `ref` antes de invocar esta funcion.
///
/// Best-effort: cualquier fallo (sin sesion, sin plugin de notificaciones
/// registrado como en los tests de widgets, etc.) se ignora en silencio para
/// no bloquear el flujo que la invoca (guardar una cuenta / terminar un
/// sync).
Future<void> rescheduleCardRemindersFromDb(AppDatabase db, NotificationsService service) async {
  try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final settings = userId == null ? null : await db.settingsDao.get(userId);
    final daysBefore = settings?.alertDaysBeforeDue ?? 3;
    final creditCards =
        (await db.accountsDao.watchActive().first).where((a) => a.type == 'credit').toList();
    await service.scheduleCardReminders(creditCards, daysBefore);
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {}
}
