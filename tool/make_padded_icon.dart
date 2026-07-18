// Genera assets/icon/icon_padded.png: un lienzo transparente de 1024x1024 con
// el logo de marca (assets/brand/logo.png, 571x571) redimensionado a ~640px y
// centrado. El icono adaptativo de Android recorta ~33% del foreground en
// mascaras circulares/squircle, asi que el logo necesita este margen de
// seguridad para no quedar cortado.
//
// Uso: dart run tool/make_padded_icon.dart
//
// Se usa un script en Dart (con el paquete `image` como dev_dependency) en
// lugar de ImageMagick porque `magick`/`convert` no estan disponibles en este
// entorno. El resultado es equivalente al comando sugerido en el brief:
//   magick assets/brand/logo.png -resize 640x640 -background none \
//     -gravity center -extent 1024x1024 assets/icon/icon_padded.png
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const canvasSize = 1024;
  const logoSize = 640;

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

  // Redimensiona el logo manteniendo transparencia y usando interpolacion
  // cubica para un resultado nitido.
  final resizedLogo = img.copyResize(
    source,
    width: logoSize,
    height: logoSize,
    interpolation: img.Interpolation.cubic,
  );

  // Lienzo transparente 1024x1024.
  final canvas = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  // Centra el logo redimensionado en el lienzo.
  final offset = (canvasSize - logoSize) ~/ 2;
  img.compositeImage(
    canvas,
    resizedLogo,
    dstX: offset,
    dstY: offset,
  );

  final outFile = File('assets/icon/icon_padded.png');
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(img.encodePng(canvas));

  stdout.writeln(
    'Generado ${outFile.path} (${canvas.width}x${canvas.height}), '
    'logo ${resizedLogo.width}x${resizedLogo.height} centrado en offset '
    '($offset, $offset).',
  );
}
