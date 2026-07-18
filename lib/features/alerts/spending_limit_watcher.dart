import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../services/notifications_service.dart';

enum LimitStatus { ok, near, exceeded }

/// Funcion pura (Task 23, Step 1 TDD): clasifica el gasto del mes contra el
/// limite configurado. `near` es >= 90% del limite (redondeado); `exceeded`
/// es estrictamente mayor al limite, asi que llegar exactamente al 100%
/// sigue siendo `near`, no `exceeded`.
LimitStatus evaluateLimit(int spentCents, int limitCents) {
  if (spentCents > limitCents) return LimitStatus.exceeded;
  if (spentCents >= (limitCents * 0.9).round()) return LimitStatus.near;
  return LimitStatus.ok;
}

/// Titulos exactos usados para la notificacion/alerta de cada umbral.
/// Ambos contienen "límite" a proposito, alineado con la heuristica de
/// icono de `AlertsScreen` (campana ambar). Tambien sirven como clave del
/// deduplicado por mes (ver `_alreadyAlertedThisMonth`): "near" y "exceeded"
/// se deduplican de forma independiente porque tienen titulos distintos.
const _nearTitle = 'Límite de gasto: 90%';
const _exceededTitle = 'Límite de gasto superado';

/// Revisa el gasto del mes actual (hora de Lima) de [userId] contra
/// `monthly_limit_cents` (`SettingsDao`, Task 15) y, si llega al 90% o
/// supera el limite, emite una notificacion + alerta local
/// (`NotificationsService.showNow`, que YA inserta en `local_alerts` -- no
/// se llama `insertAlert` aparte aqui para no duplicar el historial, ver
/// Task 22).
///
/// Maximo una notificacion por umbral por mes calendario de Lima: antes de
/// notificar se consulta `local_alerts` por una fila con el MISMO titulo
/// cuyo `createdAt` caiga dentro del mes actual (limites UTC via
/// `monthRangeUtc`). Cuando el estado es `exceeded` solo se evalua/emite esa
/// alerta (nunca tambien la de 90%: superar el limite implica haber
/// superado el 90%, mostrar ambas seria redundante).
///
/// Sin `monthly_limit_cents` configurado (null): no hace nada.
Future<void> checkSpendingLimit(AppDatabase db, NotificationsService notif, String userId) async {
  final settings = await db.settingsDao.get(userId);
  final limitCents = settings?.monthlyLimitCents;
  if (limitCents == null) return;

  final nowLima = toLima(DateTime.now().toUtc());
  final month = DateTime(nowLima.year, nowLima.month, 1);
  final spentCents = await db.transactionsDao.monthlyTotal(kind: 'expense', month: month);

  final status = evaluateLimit(spentCents, limitCents);
  if (status == LimitStatus.ok) return;

  final title = status == LimitStatus.exceeded ? _exceededTitle : _nearTitle;
  if (await _alreadyAlertedThisMonth(db, title, month)) return;

  final body = status == LimitStatus.exceeded
      ? 'Superaste tu límite mensual de ${formatMoney(limitCents)}'
      : 'Vas en ${formatMoney(spentCents)} de tu límite de ${formatMoney(limitCents)} este mes (90%)';

  await notif.showNow(title, body);
}

/// `true` si ya existe una alerta con [title] creada dentro del mes de Lima
/// que contiene [month] (un primero de mes "naive" en hora de Lima, mismo
/// formato que recibe `TransactionsDao.monthlyTotal`).
Future<bool> _alreadyAlertedThisMonth(AppDatabase db, String title, DateTime month) async {
  final (from, to) = monthRangeUtc(month);
  final existing = await (db.select(db.localAlerts)
        ..where((a) =>
            a.title.equals(title) &
            a.createdAt.isBiggerOrEqualValue(from) &
            a.createdAt.isSmallerThanValue(to))
        ..limit(1))
      .getSingleOrNull();
  return existing != null;
}
