import 'package:flutter/material.dart';

import 'finora_colors.dart';

/// Tokens de diseno del pulido UI: la fuente unica de espaciado, radios,
/// sombra, motion y degradado de marca que consumen todas las pantallas.
/// Los valores son un contrato estable — no duplicar hex (usar
/// [FinoraColors]) ni redefinir estos numeros en las pantallas.
abstract final class FinoraTokens {
  // Espaciado (escala de 4)
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;

  // Radios
  static const rInput = 12.0; // ya vigente en el tema
  static const rCard = 20.0; // ya vigente en el tema
  static const rSquircle = 24.0;
  static const rSheet = 28.0; // esquinas superiores de la sheet de contenido
  static const rPill = 999.0;

  // Sombra unica suave
  static const shadowSoft = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  // Motion
  static const dFast = Duration(milliseconds: 150);
  static const dBase = Duration(milliseconds: 250);
  static const dSlow = Duration(milliseconds: 400);
  static const curve = Curves.easeOutCubic;

  // Degradado de marca
  static const brandGradient = LinearGradient(
    colors: [FinoraColors.primary, FinoraColors.primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
