import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:isar/isar.dart';

/// Carga el núcleo nativo de Isar para toda la suite de tests.
///
/// `flutter test` no registra plugins de Flutter, así que `isar` no encuentra
/// `isar.dll`/`libisar.so`/`libisar.dylib` por la ruta por defecto y falla con
/// `Failed to load dynamic library ... error code 126`.
///
/// Solución reproducible sin copiar binarios al repositorio ni descargar nada:
/// se lee `.dart_tool/package_config.json`, se localiza el paquete
/// `isar_flutter_libs` (fijado en `pubspec.lock`) y se precarga el núcleo que
/// ya distribuye ese paquete, usando la API pública `Isar.initializeIsarCore`
/// pensada para unit tests.
///
/// `ZONE_ISAR_CORE_PATH` sigue teniendo prioridad: si está definida, los tests
/// que la usan cargan explícitamente esa biblioteca y este config no interfiere.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await _ensureIsarCoreFromPubCache();
  await testMain();
}

Future<void> _ensureIsarCoreFromPubCache() async {
  final explicit = Platform.environment['ZONE_ISAR_CORE_PATH'];
  if (explicit != null && explicit.isNotEmpty) {
    return;
  }

  final String relativePath;
  if (Platform.isWindows) {
    relativePath = 'windows/isar.dll';
  } else if (Platform.isMacOS) {
    relativePath = 'macos/libisar.dylib';
  } else if (Platform.isLinux) {
    relativePath = 'linux/libisar.so';
  } else {
    return;
  }

  try {
    final packageRoot = _findPackageRoot('isar_flutter_libs');
    if (packageRoot == null) return;

    final library = File(
      '$packageRoot${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!library.existsSync()) return;

    await Isar.initializeIsarCore(
      libraries: {Abi.current(): library.absolute.path},
    );
  } catch (error) {
    // No se enmascara el fallo real: si no se pudo precargar, los tests de Isar
    // fallarán con su propio diagnóstico (p. ej. error 126) y este mensaje
    // quedará como contexto adicional.
    stderr.writeln(
      '[flutter_test_config] No se pudo precargar Isar desde '
      'isar_flutter_libs: $error',
    );
  }
}

/// Localiza el directorio raíz de un paquete leyendo el `package_config.json`
/// generado por `flutter pub get`. Busca hacia arriba desde el cwd para tolerar
/// ejecuciones desde subdirectorios.
String? _findPackageRoot(String packageName) {
  var dir = Directory.current;
  for (var depth = 0; depth < 10; depth++) {
    final config = File(
      '${dir.path}${Platform.pathSeparator}.dart_tool'
      '${Platform.pathSeparator}package_config.json',
    );
    if (config.existsSync()) {
      return _packageRootFromConfig(config, packageName);
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

String? _packageRootFromConfig(File config, String packageName) {
  final decoded = jsonDecode(config.readAsStringSync());
  if (decoded is! Map<String, dynamic>) return null;
  final packages = decoded['packages'];
  if (packages is! List) return null;

  for (final entry in packages) {
    if (entry is! Map) continue;
    if (entry['name'] != packageName) continue;

    final rootUri = entry['rootUri'];
    if (rootUri is! String || rootUri.isEmpty) return null;

    final uri = Uri.parse(rootUri);
    final resolved = uri.isAbsolute ? uri : config.uri.resolveUri(uri);
    return Directory.fromUri(resolved).path;
  }
  return null;
}
