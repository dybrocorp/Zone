import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File('assets/logo.jpg');
  if (!file.existsSync()) {
    print('El archivo assets/logo.jpg no existe.');
    exit(1);
  }

  final image = img.decodeImage(file.readAsBytesSync());
  if (image == null) {
    print('No se decodificó la imagen.');
    exit(1);
  }

  // Iterar por los pixeles, los que sean completamente o casi negros
  // los convertiremos en el color primario Color(0xFF0F172A) => R:15, G:23, B:42
  for (final p in image) {
    // Si el pixel es lo suficientemente oscuro (considerado fondo negro)
    if (p.r < 60 && p.g < 60 && p.b < 60) {
      p.r = 15;
      p.g = 23;
      p.b = 42;
    }
  }

  // Guardarlo como un nuevo archivo PNG procesado para los iconos.
  File('assets/app_icon.png').writeAsBytesSync(img.encodePng(image));
  print('¡Logo App Icon procesado y guardado correctamente en assets/app_icon.png!');
}
