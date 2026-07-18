import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/finora_theme.dart';
import 'core/router.dart';
import 'data/sync/sync_providers.dart';
import 'features/auth/lock_screen.dart';
import 'services/notifications_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sin --dart-define-from-file=env.json las constantes llegan vacias y la
  // app fallaria recien en el primer request ("No host specified in URI").
  // Mejor fallar al arrancar con instrucciones claras.
  if (Env.supabaseUrl.isEmpty || Env.supabaseAnonKey.isEmpty) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  Intl.defaultLocale = 'es_PE';
  await initializeDateFormatting('es_PE');

  // Se resuelve el estado de bloqueo ANTES de correr la app: appLockedProvider
  // arranca en `true` por defecto, y si esperaramos a resolverlo dentro del
  // arbol de widgets el router ya habria evaluado su primer redirect con ese
  // `true`, mostrando un flash de /lock aunque el usuario no tenga biometria
  // activa (o no tenga sesion). Se usa un ProviderContainer manual para poder
  // fijar el estado real antes de runApp, y se reutiliza ese mismo container
  // (con UncontrolledProviderScope) para que databaseProvider siga siendo una
  // unica instancia de AppDatabase compartida con el resto de la app.
  final container = ProviderContainer();
  final session = Supabase.instance.client.auth.currentSession;
  var locked = false;
  if (session != null) {
    final settings = await container
        .read(databaseProvider)
        .settingsDao
        .get(session.user.id);
    locked = settings?.biometricEnabled ?? false;
  }
  container.read(appLockedProvider.notifier).state = locked;

  // Init de notificaciones locales (Task 22): canal `finora_reminders`,
  // permiso POST_NOTIFICATIONS y timezone. Best-effort: un fallo aqui (p.
  // ej. plugin no soportado en el dispositivo) no debe impedir que la app
  // arranque.
  try {
    await container.read(notificationsServiceProvider).init();
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {}

  runApp(
    UncontrolledProviderScope(container: container, child: const FinoraApp()),
  );
}

class FinoraApp extends ConsumerWidget {
  const FinoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncCoordinatorProvider);
    return MaterialApp.router(
      title: 'Finora',
      debugShowCheckedModeBanner: false,
      theme: finoraTheme(),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Pantalla de error cuando la app se lanza sin la configuracion de entorno.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finora',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.settings_suggest, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Falta la configuración de entorno',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Lanza la app con:\n'
                  'flutter run --dart-define-from-file=env.json\n\n'
                  'En Android Studio, selecciona la configuración '
                  '"Finora (env)" en el menú de ejecución.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
