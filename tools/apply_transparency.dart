import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  final file = File('assets/logo.png');
  if (!file.existsSync()) {
    print('No se encontró assets/logo.png');
    return;
  }

  final bytes = await file.readAsBytes();
  var image = img.decodeImage(bytes);

  if (image == null) {
    print('No se pudo decodificar la imagen');
    return;
  }

  if (image.numChannels < 4) {
    print('Convirtiendo a RGBA...');
    image = image.convert(numChannels: 4);
  }

  int count = 0;
  for (var i = 0; i < image.width; i++) {
    for (var j = 0; j < image.height; j++) {
      final pixel = image.getPixel(i, j);
      
      final r = pixel.r;
      final g = pixel.g;
      final b = pixel.b;

      // Umbral agresivo 140 para limpiar brillos residuales
      if (r < 140 && g < 140 && b < 140) {
        pixel.a = 0; 
        count++;
      }
    }
  }

  print('Se hicieron transparentes $count píxeles en el logo.');

  final pngBytes = img.encodePng(image);
  await File('assets/logo.png').writeAsBytes(pngBytes);
  print('Logo transparente guardado con éxito.');
}
