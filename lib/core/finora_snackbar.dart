import 'dart:async';

import 'package:flutter/material.dart';

import 'finora_colors.dart';
import 'finora_tokens.dart';

/// Notificaciones (toasts) personalizadas de Finora. Reemplazan el `SnackBar`
/// gris por defecto de Flutter por una tarjeta blanca con esquinas
/// redondeadas ([FinoraTokens.rCard]), sombra suave ([FinoraTokens.shadowSoft])
/// y un acento de color a la izquierda + icono segun la variante.
///
/// A diferencia del `SnackBar` (que siempre aparece abajo y pasa casi
/// desapercibido), estos toasts CAEN desde la parte superior sobre un
/// [Overlay] propio: entran deslizando + fundido, se auto-ocultan y se pueden
/// descartar tocando o deslizando hacia arriba. Es solo capa de presentacion:
/// las pantallas la invocan tras crear, editar, eliminar, confirmar o al
/// fallar una validacion.
///
/// ```dart
/// FinoraSnackbar.success(context, 'Categoria creada');
/// FinoraSnackbar.error(context, 'Monto invalido');
/// FinoraSnackbar.info(context, 'Sin conexion');
/// FinoraSnackbar.warning(context, 'Limite mensual alcanzado');
/// ```
abstract final class FinoraSnackbar {
  /// Toast visible en pantalla, o null si no hay ninguno. Solo se muestra uno
  /// a la vez: al pedir uno nuevo se retira el anterior (evita una cola).
  static OverlayEntry? _current;

  /// Confirmacion positiva: crear, editar, guardar, confirmar. Verde de marca.
  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
  }) => _show(context, message, _SnackVariant.success, duration);

  /// Error o validacion fallida. Rojo.
  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
  }) => _show(context, message, _SnackVariant.error, duration);

  /// Aviso neutro e informativo. Azul.
  static void info(
    BuildContext context,
    String message, {
    Duration? duration,
  }) => _show(context, message, _SnackVariant.info, duration);

  /// Advertencia no bloqueante. Ambar.
  static void warning(
    BuildContext context,
    String message, {
    Duration? duration,
  }) => _show(context, message, _SnackVariant.warning, duration);

  static void _show(
    BuildContext context,
    String message,
    _SnackVariant variant,
    Duration? duration,
  ) {
    // `rootOverlay` para que el toast quede por encima de todo (incluidas las
    // sheets/dialogos) y siga visible aunque quien lo dispara haga pop.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final (color, icon) = switch (variant) {
      _SnackVariant.success => (
        FinoraColors.primary,
        Icons.check_circle_rounded,
      ),
      _SnackVariant.error => (FinoraColors.expense, Icons.error_rounded),
      _SnackVariant.info => (FinoraColors.savings, Icons.info_rounded),
      _SnackVariant.warning => (
        FinoraColors.warning,
        Icons.warning_amber_rounded,
      ),
    };

    _dismissCurrent();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FinoraToast(
        color: color,
        icon: icon,
        message: message,
        duration: duration ?? const Duration(seconds: 3),
        onDismissed: () {
          if (identical(_current, entry)) _current = null;
          _safeRemove(entry);
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// Retira el toast visible de inmediato (sin animacion de salida), usado al
  /// mostrar uno nuevo.
  static void _dismissCurrent() {
    final current = _current;
    _current = null;
    if (current != null) _safeRemove(current);
  }

  static void _safeRemove(OverlayEntry entry) {
    if (entry.mounted) entry.remove();
  }
}

enum _SnackVariant { success, error, info, warning }

/// Widget del toast montado en el [Overlay]: se posiciona pegado arriba
/// (respetando la barra de estado con [SafeArea]), entra deslizando desde
/// fuera de pantalla con fundido, arranca un temporizador de auto-descarte y
/// permite descartarlo tocando o deslizando hacia arriba.
class _FinoraToast extends StatefulWidget {
  const _FinoraToast({
    required this.color,
    required this.icon,
    required this.message,
    required this.duration,
    required this.onDismissed,
  });

  final Color color;
  final IconData icon;
  final String message;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_FinoraToast> createState() => _FinoraToastState();
}

class _FinoraToastState extends State<_FinoraToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  late final Animation<double> _fade;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: FinoraTokens.dBase,
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, -1.2), // arranca por encima del borde superior
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: FinoraTokens.curve));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  /// Anima la salida (revierte el deslizamiento) y luego pide retirar la
  /// entrada del overlay. Idempotente: toque + temporizador no lo duplican.
  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    try {
      await _controller.reverse();
    } on TickerCanceled {
      // El widget se desmonto (p. ej. lo reemplazo otro toast) durante la
      // animacion de salida: nada que revertir.
    }
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(FinoraTokens.s16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SlideTransition(
              position: _offset,
              child: FadeTransition(
                opacity: _fade,
                child: GestureDetector(
                  onTap: _dismiss,
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < 0) _dismiss();
                  },
                  child: Material(
                    type: MaterialType.transparency,
                    child: _FinoraToastCard(
                      color: widget.color,
                      icon: widget.icon,
                      message: widget.message,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta visual del toast: fondo tenue en el tono de la variante, borde en
/// el mismo color intenso, icono a juego y el mensaje en
/// [FinoraColors.textPrimary]. El color va uniforme por toda la tarjeta (sin
/// barra lateral) para que sea legible sobre cualquier fondo, incluido el
/// header verde de marca.
class _FinoraToastCard extends StatelessWidget {
  const _FinoraToastCard({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    // Tono clarito del color de la variante: el color al 12% compuesto sobre
    // blanco (opaco estable en vez de translucido).
    final tint = Color.alphaBlend(
      color.withValues(alpha: 0.12),
      FinoraColors.surface,
    );
    return Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(FinoraTokens.rCard),
        boxShadow: FinoraTokens.shadowSoft,
        // Borde en el color intenso de la variante: define la tarjeta y la
        // separa de fondos del mismo tono.
        border: Border.all(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FinoraTokens.s12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: FinoraTokens.s12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: FinoraColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
