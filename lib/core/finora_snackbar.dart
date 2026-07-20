import 'package:flutter/material.dart';

import 'finora_colors.dart';
import 'finora_tokens.dart';

/// Notificaciones (toasts) personalizadas de Finora. Reemplazan el `SnackBar`
/// gris por defecto de Flutter por una tarjeta flotante blanca con esquinas
/// redondeadas ([FinoraTokens.rCard]), sombra suave ([FinoraTokens.shadowSoft])
/// y un acento de color a la izquierda + icono segun la variante.
///
/// Es solo capa de presentacion: las pantallas la invocan tras crear, editar,
/// eliminar, confirmar o al fallar una validacion.
///
/// ```dart
/// FinoraSnackbar.success(context, 'Categoria creada');
/// FinoraSnackbar.error(context, 'Monto invalido');
/// FinoraSnackbar.info(context, 'Sin conexion');
/// FinoraSnackbar.warning(context, 'Limite mensual alcanzado');
/// ```
abstract final class FinoraSnackbar {
  /// Confirmacion positiva: crear, editar, guardar, confirmar. Verde de marca.
  static void success(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, _SnackVariant.success, duration);

  /// Error o validacion fallida. Rojo.
  static void error(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, _SnackVariant.error, duration);

  /// Aviso neutro e informativo. Azul.
  static void info(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, _SnackVariant.info, duration);

  /// Advertencia no bloqueante. Ambar.
  static void warning(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, _SnackVariant.warning, duration);

  static void _show(
    BuildContext context,
    String message,
    _SnackVariant variant,
    Duration? duration,
  ) {
    final (color, icon) = switch (variant) {
      _SnackVariant.success => (FinoraColors.primary, Icons.check_circle_rounded),
      _SnackVariant.error => (FinoraColors.expense, Icons.error_rounded),
      _SnackVariant.info => (FinoraColors.savings, Icons.info_rounded),
      _SnackVariant.warning => (FinoraColors.warning, Icons.warning_amber_rounded),
    };
    ScaffoldMessenger.of(context)
      // Oculta el toast anterior para que no se acumule una cola.
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          // El contenedor interno aporta fondo, radio y sombra; el SnackBar en
          // si es transparente y sin elevacion.
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.all(FinoraTokens.s16),
          duration: duration ?? const Duration(seconds: 3),
          content: _FinoraToast(color: color, icon: icon, message: message),
        ),
      );
  }
}

enum _SnackVariant { success, error, info, warning }

/// Tarjeta visual del toast: acento de color a la izquierda, icono en un
/// circulo tenue del mismo color y el mensaje en [FinoraColors.textPrimary].
class _FinoraToast extends StatelessWidget {
  const _FinoraToast({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FinoraColors.surface,
        borderRadius: BorderRadius.circular(FinoraTokens.rCard),
        boxShadow: FinoraTokens.shadowSoft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FinoraTokens.rCard),
        // IntrinsicHeight para que la barra de acento se estire a la altura del
        // contenido (mensajes de una o dos lineas).
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(FinoraTokens.s12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          // Color al 12% compuesto sobre blanco: tono opaco
                          // estable en vez de translucido.
                          color: Color.alphaBlend(
                            color.withValues(alpha: 0.12),
                            FinoraColors.surface,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 20, color: color),
                      ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
