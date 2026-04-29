# Zone

**Conoce Personas Que Están Cerca De Ti, Sin La Presión De Hablar En Persona**

Zone es una red social basada en la proximidad (vía Bluetooth) y en la privacidad. Diseñada al estilo de un radar, te permite descubrir personas a tu alrededor, chatear de forma segura a través de mensajería con cifrado de extremo a extremo (E2EE con X25519/ChaCha20-Poly1305) y compartir tus redes sociales (Instagram, Facebook, TikTok) sólo con quienes tú decidas.

## Características Principales

- **Descubrimiento por Radar (Bluetooth)**: Encuentra personas cercanas de forma pasiva y privada utilizando tecnología Bluetooth Low Energy (BLE).
- **Privacidad Primero**: No recopilamos datos innecesarios. Se te asigna un ID único sin necesidad de vincular cuentas de correo o números de teléfono.
- **Mensajería E2EE**: Todos los mensajes están protegidos mediante cifrado de extremo a extremo, asegurando que nadie más pueda leer tus conversaciones.
- **Intercambio Seguro de Redes Sociales**: Controla la visibilidad de tus perfiles mediante permisos configurables. 
- **Diseño Moderno**: Interfaz oscura (dark-themed), moderna y fácil de usar, diseñada para la generación actual.

## Tecnologías Utilizadas

- **Frontend**: Flutter (Dart)
- **Backend / DB**: Supabase (Tiempo Real, Auth y Base de Datos)
- **Seguridad**: X25519, ChaCha20-Poly1305 para E2EE
- **Conectividad Local**: Integración con APIs nativas de Bluetooth

## Configuración del Proyecto

Si deseas clonar y ejecutar el proyecto localmente, asegúrate de tener instalado Flutter.

```bash
git clone https://github.com/dybrocorp/Zone.git
cd Zone
flutter pub get
flutter run
```

## Estructura del Proyecto

El código fuente principal se encuentra en `lib/`:
- `/screens` Las vistas principales de la aplicación (radar, chat, perfil).
- `/services` Lógica de negocio, conexión Bluetooth, y servicios de cifrado.

## Contacto
Desarrollado por [Dybro Corp](https://github.com/dybrocorp).
