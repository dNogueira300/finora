import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_providers.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/lock_screen.dart';

/// Decision pura de redirect, extraida para poder testearla sin depender de
/// go_router ni de Supabase. `location` es la ruta actualmente resolviendose
/// (equivalente a `state.matchedLocation`).
///
/// Reglas (en este orden):
/// 1. Sin sesion -> `/login` (salvo que ya este ahi).
/// 2. Con sesion y bloqueada -> `/lock` (salvo que ya este ahi).
/// 3. Con sesion, desbloqueada, y en `/login` o `/lock` -> `/`.
/// 4. En cualquier otro caso, no redirige.
String? redirectDecision({
  required bool loggedIn,
  required bool locked,
  required String location,
}) {
  final atLogin = location == '/login';
  final atLock = location == '/lock';
  if (!loggedIn) return atLogin ? null : '/login';
  if (locked && !atLock) return '/lock';
  if (!locked && (atLogin || atLock)) return '/';
  return null;
}

/// Notifier que refresca el router cuando cambia el bloqueo o el estado de
/// auth (login/logout), para que el redirect se vuelva a evaluar.
class RouterRefresh extends ChangeNotifier {
  RouterRefresh(Ref ref) {
    ref.listen(appLockedProvider, (_, _) => notifyListeners());
    ref.listen(authStateProvider, (_, next) {
      // Al cerrar sesion, el usuario no debe encontrar la app bloqueada en
      // el proximo login: se resetea appLockedProvider aqui, antes de
      // notificar, para que el redirect subsiguiente ya vea `locked: false`.
      // En un login recien hecho (evento signedIn con sesion no nula) no se
      // fuerza el bloqueo: se deja el estado tal cual esta.
      if (next.valueOrNull?.session == null) {
        ref.read(appLockedProvider.notifier).state = false;
      }
      notifyListeners();
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    refreshListenable: refresh,
    initialLocation: '/',
    redirect: (context, state) {
      final loggedIn = ref.read(authRepositoryProvider).currentUserId != null;
      final locked = ref.read(appLockedProvider);
      return redirectDecision(
        loggedIn: loggedIn,
        locked: locked,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/lock', builder: (_, _) => const LockScreen()),
      GoRoute(path: '/', builder: (_, _) => const _Placeholder('Dashboard')),
      GoRoute(path: '/add', builder: (_, _) => const _Placeholder('Nuevo gasto')),
      GoRoute(path: '/cards', builder: (_, _) => const _Placeholder('Mis tarjetas')),
      GoRoute(path: '/calendar', builder: (_, _) => const _Placeholder('Calendario')),
      GoRoute(path: '/stats', builder: (_, _) => const _Placeholder('Estadísticas')),
      GoRoute(path: '/goals', builder: (_, _) => const _Placeholder('Metas')),
      GoRoute(path: '/alerts', builder: (_, _) => const _Placeholder('Alertas')),
      GoRoute(path: '/settings', builder: (_, _) => const _Placeholder('Configuración')),
    ],
  );
});

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.title);
  final String title;
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(title)));
}
