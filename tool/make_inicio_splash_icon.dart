// Genera assets/icon/splash_inicio_padded.png: un lienzo TRANSPARENTE de
// 1152x1152 con el logo de inicio (assets/brand/finora_inicio.png)
// redimensionado a ~544x544 y centrado. A diferencia de
// tool/make_splash_icon.dart, aqui NO se hornea un circulo blanco detras:
// el logo va directo sobre el fondo verde del splash (requisito del
// usuario, mismo criterio que el login/lock).
//
// Motivacion del padding: en Android 12+ el splash aplica una mascara
// circular sobre el centro (~768px de un lienzo de 1152). Un cuadrado de
// 544px cabe entero en ese circulo (diagonal 544*sqrt(2) ~ 769), asi que
// las esquinas redondeadas del logo nunca se recortan.
//
// Uso: dart run tool/make_inicio_splash_icon.dart
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const canvasSize = 1152;
  const logoSize = 544;

  final sourceFile = File('assets/brand/finora_inicio.png');
  if (!sourceFile.existsSync()) {
    stderr.writeln('No se encontro assets/brand/finora_inicio.png');
    exit(1);
  }

  final source = img.decodePng(sourceFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('No se pudo decodificar assets/brand/finora_inicio.png');
    exit(1);
  }

  final canvas = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );

  final logo = img.copyResize(
    source,
    width: logoSize,
    height: logoSize,
    interpolation: img.Interpolation.cubic,
  );

  img.compositeImage(
    canvas,
    logo,
    dstX: (canvasSize - logoSize) ~/ 2,
    dstY: (canvasSize - logoSize) ~/ 2,
  );

  final out = File('assets/icon/splash_inicio_padded.png')
    ..writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Generado ${out.path} (${canvasSize}x$canvasSize, logo $logoSize)');
}
