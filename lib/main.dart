import 'dart:async';

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
  runApp(const ProviderScope(child: FinoraApp()));
}

class FinoraApp extends ConsumerStatefulWidget {
  const FinoraApp({super.key});

  @override
  ConsumerState<FinoraApp> createState() => _FinoraAppState();
}

class _FinoraAppState extends ConsumerState<FinoraApp> {
  @override
  void initState() {
    super.initState();
    // No se espera este future: la primera pantalla puede mostrar el lock
    // brevemente mientras se resuelve, pero el estado por defecto de
    // appLockedProvider (true) solo debe persistir si de verdad corresponde.
    unawaited(_initLockState());
  }

  Future<void> _initLockState() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // Sin sesion no hay nada que desbloquear: el redirect del router
      // manda a /login de todas formas.
      ref.read(appLockedProvider.notifier).state = false;
      return;
    }
    final db = ref.read(databaseProvider);
    final settings = await db.settingsDao.get(session.user.id);
    if (!mounted) return;
    ref.read(appLockedProvider.notifier).state =
        settings?.biometricEnabled ?? false;
  }

  @override
  Widget build(BuildContext context) {
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
