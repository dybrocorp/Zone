import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuración de Supabase para la aplicación.
///
/// Fuentes de configuración, en orden de prioridad:
///
/// 1. **Compile-time `--dart-define` (producción):**
///    ```sh
///    flutter run  --dart-define-from-file=.env
///    flutter build apk --dart-define-from-file=.env
///    ```
///    Los valores quedan embebidos en el binario y NO se empaqueta ningún
///    archivo `.env` como asset.
///
/// 2. **Dev fallback:** si no se pasaron `--dart-define`, se intenta cargar
///    `.env` vía `flutter_dotenv` (solo funciona si `.env` está declarado
///    como asset en `pubspec.yaml`). El fallback es tolerante: si el asset
///    no existe, no lanza error y se reporta configuración ausente.
///
/// Si no hay ninguna fuente disponible, `resolve()` devuelve valores nulos
/// y la pantalla de arranque muestra un mensaje claro en lugar de crashear.
class EnvConfig {
  EnvConfig._();

  /// `SUPABASE_URL` inyectada en compilación (vacío si no se definió).
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL');

  /// `SUPABASE_ANON_KEY` inyectada en compilación (vacío si no se definió).
  /// Es una clave *publishable* diseñada para ir en el cliente.
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get _hasDartDefine =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  /// Resuelve la configuración de Supabase.
  ///
  /// Devuelve un registro con `url` y `anonKey`; ambos pueden ser `null`
  /// si no hay fuente de configuración disponible.
  static Future<({String? url, String? anonKey})> resolve() async {
    // 1. Fuente principal: valores de compilación (producción).
    if (_hasDartDefine) {
      return (url: supabaseUrl, anonKey: supabaseAnonKey);
    }

    // 2. Fallback dev: dotenv opcional (no debe crashear si no hay asset).
    //    Nota: si `dotenv.load` falla, `DotEnv` queda sin inicializar y el
    //    getter `dotenv.env` lanza `NotInitializedError` — por eso las
    //    lecturas van dentro del mismo bloque try/catch.
    String url = '';
    String anonKey = '';
    try {
      await dotenv.load(fileName: '.env');
      url = dotenv.env['SUPABASE_URL']?.trim() ?? '';
      anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
    } catch (_) {
      // Sin asset `.env` en este entorno (normal en tests / builds limpios).
    }

    if (url.isEmpty || anonKey.isEmpty) {
      return (url: null, anonKey: null);
    }
    return (url: url, anonKey: anonKey);
  }
}