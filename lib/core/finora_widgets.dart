import 'package:flutter/material.dart';

import 'finora_colors.dart';
import 'finora_tokens.dart';

/// Widgets base reutilizables del pulido UI (Tarea 1). Son la fundacion de
/// presentacion que consumen las pantallas: cabecera de marca con degradado,
/// sheet de contenido con esquinas superiores redondeadas, cabecera de
/// seccion y accion rapida (squircle). Solo capa de presentacion.

/// Contenedor con el [FinoraTokens.brandGradient] que sirve de cabecera de
/// marca. Acepta un [child] y una altura flexible; no incluye AppBar propio.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.child,
    this.height,
    this.padding = const EdgeInsets.all(FinoraTokens.s16),
  });

  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      padding: padding,
      decoration: const BoxDecoration(gradient: FinoraTokens.brandGradient),
      child: child,
    );
  }
}

/// Pagina con cabecera de marca: barra superior sobre el degradado (boton de
/// volver si la ruta se puede "pop", titulo en blanco y acciones opcionales)
/// y debajo el contenido sobre [FinoraColors.background] con las esquinas
/// superiores redondeadas ([FinoraTokens.rSheet]), como la sheet del
/// dashboard. Pensada como `body` de un `Scaffold` sin `AppBar`.
class BrandPage extends StatelessWidget {
  const BrandPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: FinoraTokens.brandGradient),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FinoraTokens.s8,
                FinoraTokens.s8,
                FinoraTokens.s8,
                FinoraTokens.s16,
              ),
              child: Row(
                children: [
                  if (canPop)
                    const BackButton(color: Colors.white)
                  else
                    const SizedBox(width: FinoraTokens.s8),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(FinoraTokens.rSheet),
                ),
                child: ColoredBox(
                  color: FinoraColors.background,
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet de contenido: envuelve el contenido scrolleable de una pantalla con
/// fondo [FinoraColors.background] y esquinas superiores redondeadas
/// ([FinoraTokens.rSheet]), sentandose visualmente sobre el [BrandHeader].
class ContentSheet extends StatelessWidget {
  const ContentSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FinoraTokens.s16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: const BoxDecoration(
        color: FinoraColors.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FinoraTokens.rSheet),
        ),
      ),
      child: child,
    );
  }
}

/// Cabecera de seccion: titulo en negrita a la izquierda y un boton opcional
/// "Ver todos" con chevron a la derecha (cuando se pasa [onSeeAll]).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: FinoraColors.textPrimary,
            ),
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              foregroundColor: FinoraColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: FinoraTokens.s8),
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ver todos'),
                Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

/// Accion rapida: un cuadrado con esquinas suaves (64x64, radio
/// [FinoraTokens.rSquircle]) con icono verde y un label debajo. Usa [InkWell]
/// para dar feedback tactil visible (ripple). La variante [highlighted]
/// resalta la accion con fondo primary al 12% y borde primary.
class Squircle extends StatelessWidget {
  const Squircle({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  static const double _size = 64;

  @override
  Widget build(BuildContext context) {
    // #16A34A al 12% compuesto sobre blanco (superficie), para un tono opaco
    // estable en vez de translucido (evita mezclas raras al superponerse).
    final background = highlighted
        ? Color.alphaBlend(
            FinoraColors.primary.withValues(alpha: 0.12),
            FinoraColors.surface,
          )
        : FinoraColors.surface;
    final borderColor =
        highlighted ? FinoraColors.primary : FinoraColors.border;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(FinoraTokens.rSquircle),
            border: Border.all(color: borderColor),
            boxShadow: FinoraTokens.shadowSoft,
          ),
          // Material transparente + InkWell para que el ripple se recorte al
          // radio del squircle y quede por encima del fondo del Container.
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(FinoraTokens.rSquircle),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Icon(icon, size: 28, color: FinoraColors.primary),
              ),
            ),
          ),
        ),
        const SizedBox(height: FinoraTokens.s8),
        SizedBox(
          width: _size,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: FinoraColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
