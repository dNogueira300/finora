import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/finora_colors.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import 'alerts_dao_ext.dart';

final _alertsProvider = StreamProvider.autoDispose<List<LocalAlert>>((ref) {
  return ref.watch(databaseProvider).watchAlerts();
});

/// Cantidad de alertas no leidas, usado tanto por `AlertsScreen` como por el
/// badge de la campana en el dashboard (`ref.watch(unreadCountProvider)`).
final unreadCountProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(databaseProvider).unreadCount();
});

/// Quita tildes de las vocales para poder comparar titulos sin importar si
/// vienen con o sin acento (p. ej. "límite" y "limite" deben resolver igual).
String _stripAccents(String s) => s
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u');

/// Infiere el icono/color de una alerta a partir de su titulo, ya que
/// `LocalAlerts` (Task 4) no tiene columna de tipo. Las tareas 22-23 deben
/// alinear los titulos que generan con esta heuristica:
/// - contiene "limite" -> campana ambar (alerta de limite de gasto).
/// - contiene "vencimiento"/"pago"/"cierre" -> tarjeta azul (vencimiento de
///   cuenta de credito).
/// - cualquier otro caso -> campana neutra.
(IconData, Color) _alertIcon(String title) {
  final t = _stripAccents(title.toLowerCase());
  if (t.contains('limite')) {
    return (Icons.notifications, FinoraColors.warning);
  }
  if (t.contains('vencimiento') || t.contains('pago') || t.contains('cierre')) {
    return (Icons.credit_card, FinoraColors.savings);
  }
  return (Icons.notifications_none, FinoraColors.textSecondary);
}

/// Etiqueta del encabezado de grupo para el dia [limaDay] (ya truncado a
/// año/mes/dia en hora de Lima): "Hoy", "Ayer" o la fecha en español.
String _dayLabel(DateTime limaDay) {
  final today = toLima(DateTime.now().toUtc());
  final todayDate = DateTime(today.year, today.month, today.day);
  final diff = todayDate.difference(limaDay).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  return DateFormat('d MMMM yyyy', 'es').format(limaDay);
}

/// Agrupa [alerts] por dia calendario de Lima, preservando el orden
/// descendente de `watchAlerts()` (mas reciente primero), de modo que cada
/// grupo quede contiguo sin necesidad de reordenar.
Map<String, List<LocalAlert>> _groupByDay(List<LocalAlert> alerts) {
  final groups = <String, List<LocalAlert>>{};
  for (final a in alerts) {
    final lima = toLima(a.createdAt);
    final day = DateTime(lima.year, lima.month, lima.day);
    groups.putIfAbsent(_dayLabel(day), () => []).add(a);
  }
  return groups;
}

/// Pantalla "Alertas y Notificaciones" (Task 20, referencia Stitch): historial
/// local de alertas agrupado por dia, con icono segun tipo inferido del
/// titulo (ver `_alertIcon`), swipe-to-dismiss para borrar y accion
/// "Marcar todas como leídas". Las tareas 22-23 llaman `insertAlert` cada vez
/// que generan una notificacion del sistema.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(_alertsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas'),
        actions: [
          TextButton(
            onPressed: () => ref.read(databaseProvider).markAllRead(),
            child: const Text('Marcar todas como leídas'),
          ),
        ],
      ),
      body: SafeArea(
        child: alertsAsync.when(
          data: (alerts) {
            if (alerts.isEmpty) return const _EmptyState();
            final groups = _groupByDay(alerts);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 8),
                    child: Text(entry.key, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  for (final alert in entry.value) _AlertTile(alert: alert),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('No se pudo cargar: $e')),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Sin alertas por ahora',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: FinoraColors.textSecondary),
        ),
      ),
    );
  }
}

/// Fila de una alerta: icono segun tipo, titulo (en negrita si no esta
/// leida), cuerpo y hora en Lima. Swipe hacia la izquierda la borra
/// fisicamente (`deleteAlert`), ya que `LocalAlerts` no tiene soft-delete.
class _AlertTile extends ConsumerWidget {
  const _AlertTile({required this.alert});
  final LocalAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color) = _alertIcon(alert.title);
    final time = DateFormat('HH:mm').format(toLima(alert.createdAt));

    return Dismissible(
      key: ValueKey(alert.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: FinoraColors.expense,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => ref.read(databaseProvider).deleteAlert(alert.id),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          title: Text(
            alert.title,
            style: TextStyle(fontWeight: alert.isRead ? FontWeight.normal : FontWeight.bold),
          ),
          subtitle: Text(alert.body),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(time, style: const TextStyle(color: FinoraColors.textSecondary, fontSize: 12)),
              if (!alert.isRead) ...[
                const SizedBox(height: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: FinoraColors.primary, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
