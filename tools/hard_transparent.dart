import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  final file = File('assets/logo.png');
  if (!file.existsSync()) {
    stdout.writeln('No se encontró assets/logo.png');
    return;
  }

  final bytes = await file.readAsBytes();
  var image = img.decodeImage(bytes);

  if (image == null) {
    stdout.writeln('No se pudo decodificar la imagen');
    return;
  }

  // Asegurarnos de que el modo de color soporte transparencia
  if (image.numChannels < 4) {
    stdout.writeln('Convirtiendo a RGBA...');
    image = image.convert(numChannels: 4);
  }

  int count = 0;
  for (var i = 0; i < image.width; i++) {
    for (var j = 0; j < image.height; j++) {
      final pixel = image.getPixel(i, j);
      
      final r = pixel.r;
      final g = pixel.g;
      final b = pixel.b;

      // Un umbral muy generoso para capturar el negro y el azul muy oscuro
      // Si la suma de R + G + B es baja, es un color oscuro o un glow residual.
      if (r < 140 && g < 140 && b < 140) {
        pixel.a = 0; 
        count++;
      }
    }
  }

  stdout.writeln('Se hicieron transparentes $count píxeles.');

  final pngBytes = img.encodePng(image);
  await File('assets/logo.png').writeAsBytes(pngBytes);
  await File('assets/app_icon.png').writeAsBytes(pngBytes);
  
  stdout.writeln('Logo guardado con éxito.');
}
