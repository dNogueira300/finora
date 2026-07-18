import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'finora_colors.dart';

/// Shell de navegacion compartido por las 5 pantallas principales (Task 14):
/// bottom bar con 4 destinos + FAB central verde que abre `/add`.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _tabs = ['/', '/cards', '/stats', '/settings'];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _tabs.indexWhere((t) => t == location).clamp(0, 3);
    return Scaffold(
      body: child,
      floatingActionButton: FloatingActionButton(
        heroTag: 'shell-fab',
        onPressed: () => context.push('/add'),
        backgroundColor: FinoraColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
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

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = selected ? FinoraColors.secondary : FinoraColors.textSecondary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ]),
      ),
    );
  }
}
