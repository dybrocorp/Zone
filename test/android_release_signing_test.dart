import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard de regresión de la Fase C: un build de release nunca debe volver a
/// firmarse con la clave de debug, y las credenciales/keystores no deben poder
/// commitearse por accidente.
void main() {
  late Directory root;

  setUpAll(() {
    root = _projectRoot();
  });

  test('release no usa la firma de debug y falla si falta configuración', () {
    final gradle = File(
      '${root.path}${Platform.pathSeparator}android${Platform.pathSeparator}'
      'app${Platform.pathSeparator}build.gradle.kts',
    ).readAsStringSync();

    expect(
      gradle,
      isNot(contains('signingConfigs.getByName("debug")')),
      reason: 'release no puede firmarse con la clave de debug',
    );
    expect(
      gradle,
      contains('Release signing is not configured'),
      reason: 'el build debe fallar con un mensaje claro si falta la firma',
    );
    expect(gradle, contains('ZONE_KEYSTORE_PATH'));
    expect(gradle, contains('ZONE_KEYSTORE_PASSWORD'));
    expect(gradle, contains('ZONE_KEY_ALIAS'));
    expect(gradle, contains('ZONE_KEY_PASSWORD'));
  });

  test('key.properties y keystores están ignorados por git', () {
    final androidIgnore = File(
      '${root.path}${Platform.pathSeparator}android${Platform.pathSeparator}.gitignore',
    ).readAsStringSync();
    expect(androidIgnore, contains('key.properties'));
    expect(androidIgnore, contains('*.jks'));
    expect(androidIgnore, contains('*.keystore'));

    final rootIgnore = File(
      '${root.path}${Platform.pathSeparator}.gitignore',
    ).readAsStringSync();
    expect(rootIgnore, contains('android/key.properties'));
    expect(rootIgnore, contains('*.jks'));
    expect(rootIgnore, contains('*.keystore'));
  });

  test('el ejemplo de firma no contiene credenciales reales', () {
    final example = File(
      '${root.path}${Platform.pathSeparator}android${Platform.pathSeparator}'
      'key.properties.example',
    ).readAsStringSync();

    expect(example, contains('CHANGE_ME'));
    expect(example, contains('storeFile='));
    expect(example, contains('keyAlias='));
    expect(
      example,
      isNot(contains('storePassword=testpass')),
      reason: 'el ejemplo no puede incluir contraseñas de prueba o reales',
    );
  });
}

Directory _projectRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 10; i++) {
    final manifest = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
    if (manifest.existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('No se encontró pubspec.yaml desde ${Directory.current.path}');
}
