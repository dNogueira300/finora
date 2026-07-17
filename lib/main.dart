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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
      url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
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
    final settings =
        await container.read(databaseProvider).settingsDao.get(session.user.id);
    locked = settings?.biometricEnabled ?? false;
  }
  container.read(appLockedProvider.notifier).state = locked;

  runApp(UncontrolledProviderScope(
    container: container,
    child: const FinoraApp(),
  ));
}

class FinoraApp extends ConsumerWidget {
  const FinoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Finora',
      theme: finoraTheme(),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
