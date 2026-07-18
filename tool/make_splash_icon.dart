// Genera assets/icon/splash_icon.png: un lienzo transparente de 1152x1152 con
// un circulo blanco solido de diametro ~768 centrado, y encima el logo de
// marca (assets/brand/logo.png) redimensionado a ~560x560 y centrado.
//
// Motivacion: en Android 12+ el splash screen aplica una mascara circular
// sobre el centro (~2/3) del icono. Si se usa el logo cuadrado tal cual,
// los bordes duros del cuadrado quedan recortados de forma irregular segun
// el launcher. Al hornear un circulo blanco solido detras del logo, el
// resultado es siempre un "plato" circular limpio que contrasta bien sobre
// el fondo verde de marca (#16A34A), sin depender del recorte de mascara.
//
// Uso: dart run tool/make_splash_icon.dart
//
// Se usa un script en Dart (con el paquete `image` como dev_dependency) en
// lugar de ImageMagick porque `magick`/`convert` no estan disponibles en este
// entorno, siguiendo el mismo patron que tool/make_padded_icon.dart.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const canvasSize = 1152;
  const circleDiameter = 768;
  const logoSize = 560;

  final sourceFile = File('assets/brand/logo.png');
  if (!sourceFile.existsSync()) {
    stderr.writeln('No se encontro assets/brand/logo.png');
    exit(1);
  }

  final sourceBytes = sourceFile.readAsBytesSync();
  final source = img.decodePng(sourceBytes);
  if (source == null) {
    stderr.writeln('No se pudo decodificar assets/brand/logo.png como PNG');
    exit(1);
  }

  // Lienzo transparente 1152x1152.
  final canvas = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  // Circulo blanco solido centrado, diametro ~768 (area de mascara Android 12).
  final center = canvasSize / 2;
  final radius = circleDiameter / 2;
  img.fillCircle(
    canvas,
    x: center.round(),
    y: center.round(),
    radius: radius.round(),
    color: img.ColorRgba8(255, 255, 255, 255),
    antialias: true,
  );

  // Redimensiona el logo manteniendo transparencia y usando interpolacion
  // cubica para un resultado nitido.
  final resizedLogo = img.copyResize(
    source,
    width: logoSize,
    height: logoSize,
    interpolation: img.Interpolation.cubic,
  );

  // Centra el logo redimensionado sobre el circulo blanco.
  final offset = ((canvasSize - logoSize) / 2).round();
  img.compositeImage(
    canvas,
    resizedLogo,
    dstX: offset,
    dstY: offset,
  );

  final outFile = File('assets/icon/splash_icon.png');
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(img.encodePng(canvas));

  stdout.writeln(
    'Generado ${outFile.path} (${canvas.width}x${canvas.height}), '
    'circulo blanco diametro $circleDiameter, '
    'logo ${resizedLogo.width}x${resizedLogo.height} centrado en offset '
    '($offset, $offset).',
  );
}
