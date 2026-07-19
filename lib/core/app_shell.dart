import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'finora_colors.dart';
import 'finora_tokens.dart';

/// Shell de navegacion compartido por las 5 pantallas principales (Task 14):
/// bottom bar con notch + FAB central circular que abre `/add`.
///
/// El tab activo se resuelve con un mapeo explicito ruta -> indice
/// ([_indexForLocation]); las rutas que viven dentro del shell pero no son
/// pestañas (p.ej. `/goals`) devuelven `-1` = ningun tab resaltado (fix T14,
/// antes el `.clamp(0,3)` resaltaba "Inicio" por error).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  /// Rutas de las 4 pestañas, en orden de aparicion en la barra.
  static const _tabRoutes = ['/', '/cards', '/stats', '/settings'];

  /// Indice de la pestaña activa para [location], o `-1` si la ruta no es una
  /// pestaña (ningun destino se resalta).
  static int _indexForLocation(String location) => _tabRoutes.indexOf(location);

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexForLocation(location);
    return Scaffold(
      // El FAB y la barra inferior quedan detras del teclado en vez de subir
      // con el: las pantallas hijas tienen su propio Scaffold que si aplica
      // el inset del teclado a su contenido.
      resizeToAvoidBottomInset: false,
      body: child,
      floatingActionButton: FloatingActionButton(
        heroTag: 'shell-fab',
        onPressed: () => context.push('/add'),
        backgroundColor: FinoraColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        highlightElevation: 4,
        // Circulo perfecto (requisito del usuario) con un borde suave verde
        // claro (primary aclarado sobre blanco) que lo separa del notch.
        shape: CircleBorder(
          side: BorderSide(
            color: Color.alphaBlend(
              FinoraColors.primary.withValues(alpha: 0.35),
              FinoraColors.surface,
            ),
            width: 3,
          ),
        ),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: const _LowerCenterDocked(),
      bottomNavigationBar: BottomAppBar(
        color: FinoraColors.surface,
        // Evita el tinte de superficie de M3 sobre la elevacion.
        surfaceTintColor: FinoraColors.surface,
        // Sombra suave hacia arriba, separando la barra del contenido.
        shadowColor: FinoraTokens.shadowSoft.first.color,
        elevation: 8,
        shape: const CircularNotchedRectangle(),
        notchMargin: FinoraTokens.s8,
        height: 64,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavIcon(icon: Icons.home_rounded, label: 'Inicio', selected: index == 0, onTap: () => context.go('/')),
            _NavIcon(icon: Icons.credit_card, label: 'Tarjetas', selected: index == 1, onTap: () => context.go('/cards')),
            const SizedBox(width: 48),
            _NavIcon(icon: Icons.bar_chart_rounded, label: 'Análisis', selected: index == 2, onTap: () => context.go('/stats')),
            _NavIcon(icon: Icons.person_rounded, label: 'Perfil', selected: index == 3, onTap: () => context.go('/settings')),
          ],
        ),
      ),
    );
  }
}

/// `centerDocked` desplazado 6px hacia abajo: el FAB (56px) queda ~40% por
/// encima del borde superior de la barra y ~60% dentro, en vez del 50-50 del
/// `centerDocked` estandar.
class _LowerCenterDocked extends FloatingActionButtonLocation {
  const _LowerCenterDocked();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final base =
        FloatingActionButtonLocation.centerDocked.getOffset(scaffoldGeometry);
    return Offset(base.dx, base.dy + 6);
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Seleccionado -> primary; resto -> textSecondary. El color se interpola
    // suavemente al cambiar de pestaña (dFast/easeOutCubic), sin bloquear el
    // toque: la navegacion ya es instantanea, el color solo la acompaña.
    final target = selected ? FinoraColors.primary : FinoraColors.textSecondary;
    return TweenAnimationBuilder<Color?>(
      duration: FinoraTokens.dFast,
      curve: FinoraTokens.curve,
      tween: ColorTween(begin: target, end: target),
      builder: (context, color, _) {
        final c = color ?? target;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FinoraTokens.rPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FinoraTokens.s12, vertical: FinoraTokens.s8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: c),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: c,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
