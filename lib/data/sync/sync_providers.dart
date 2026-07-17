import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import '../local/seed.dart';
import '../remote/supabase_remote.dart';
import 'sync_engine.dart';

/// Estado de sincronizacion expuesto a la UI (indicadores, banners, etc).
enum SyncStatus { idle, syncing, offline, error }

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final syncEngineProvider = Provider<SyncEngine>((ref) => SyncEngine(
    ref.watch(databaseProvider), SupabaseRemote(Supabase.instance.client)));

final syncStatusProvider = StateProvider<SyncStatus>((_) => SyncStatus.idle);

/// Orquesta disparos automaticos de `SyncEngine.synchronize()`: al iniciar
/// sesion, al recuperar conectividad, al volver a foreground, cada 5 min y
/// tras cada escritura local (con debounce de 5 s).
///
/// Cuidado: el listener de `tableUpdates` tambien se dispara cuando el
/// propio sync escribe filas al hacer `pull()`. Para evitar un bucle
/// perpetuo de no-ops se combinan dos defensas:
///  1. El listener esta acotado a las 5 tablas sincronizables (no a todas
///     las tablas de la DB), asi que escrituras a `SyncState` (o a futuras
///     tablas solo-locales como `LocalAlerts`) nunca lo rearman.
///  2. `SyncEngine.pull()` solo persiste la marca de agua (`SyncState`)
///     cuando de verdad avanzo; si no llegaron filas nuevas no escribe nada.
/// Ademas, el flag `_running` mas el debounce de 5 s evitan bucles: mientras
/// `trigger()` esta en curso, las nuevas invocaciones se ignoran, y el push
/// de una segunda pasada no encuentra filas sucias (ya se marcaron limpias)
/// por lo que termina en no-op.
class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) trigger();
    });
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((s) async {
      if (s.event == AuthChangeEvent.signedIn) {
        try {
          await seedDefaultCategories(_ref.read(databaseProvider));
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {
          // El sembrado de categorias por defecto es best-effort: si falla no
          // debe bloquear el sync (el usuario ya inicio sesion y puede tener
          // datos remotos pendientes de traer).
        }
        trigger();
      }
    });
    final db = _ref.read(databaseProvider);
    _dbSub = db
        .tableUpdates(TableUpdateQuery.onAllTables([
          db.accounts,
          db.categories,
          db.transactions,
          db.savingsGoals,
          db.userSettings,
        ]))
        .listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 5), trigger);
    });
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => trigger());
  }

  final Ref _ref;
  StreamSubscription? _connSub, _authSub, _dbSub;
  Timer? _debounce, _periodic;
  bool _running = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) trigger();
  }

  Future<void> trigger() async {
    if (_running) return;
    if (Supabase.instance.client.auth.currentSession == null) return;
    final conn = await Connectivity().checkConnectivity();
    if (conn.contains(ConnectivityResult.none)) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.offline;
      return;
    }
    try {
      _running = true;
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
      await _ref.read(syncEngineProvider).synchronize();
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    } catch (_) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
    } finally {
      _running = false;
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _authSub?.cancel();
    _dbSub?.cancel();
    _debounce?.cancel();
    _periodic?.cancel();
  }
}

/// Construccion perezosa: `SyncCoordinator` solo se instancia cuando algun
/// widget hace `ref.watch(syncCoordinatorProvider)` (en `FinoraApp.build`).
/// Esto evita tocar `Supabase.instance` / plugins de plataforma en tests que
/// solo ejercitan otros providers de este archivo.
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final c = SyncCoordinator(ref);
  ref.onDispose(c.dispose);
  return c;
});
