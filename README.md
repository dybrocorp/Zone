# Zone - Proximity Social Network

**Descubre a quienes te rodean, sin perder tu privacidad.**

Zone es una plataforma de red social revolucionaria basada en la proximidad física (vía Bluetooth Low Energy) y el anonimato total. Diseñada con una estética moderna "ShareIt style", Zone te permite detectar personas en tu "radar" local, establecer conexiones seguras y chatear mediante un protocolo de cifrado de extremo a extremo (E2EE) de grado industrial.

## 🚀 Características Principales

- **Radar de Proximidad (BLE)**: Descubrimiento pasivo de usuarios cercanos sin necesidad de GPS, protegiendo tu ubicación exacta.
- **Privacidad Radical**: Sin correos, sin números de teléfono. Todo se basa en tu **ZONE-ID** único y claves criptográficas locales.
- **Mensajería E2EE**: Comunicación protegida por **X25519** (intercambio de claves) y **ChaCha20-Poly1305** (cifrado de mensajes).
- **Social Connect**: Comparte tus perfiles de Instagram, Facebook o TikTok de forma selectiva. Tú decides quién ve qué.
- **Modo Timidez (Stealth)**: Mira quién está cerca sin ser detectado en el radar de los demás.
- **Hardened Backend**: Servidores Supabase con auditoría de seguridad, políticas RLS estrictas y funciones protegidas.

## 🛠️ Stack Tecnológico

- **Framework**: Flutter (Dart)
- **Backend**: Supabase (PostgreSQL, Realtime, Storage)
- **Seguridad**: Ed25519 para firmas, X25519 para E2EE, PBKDF2 para derivación de claves locales.
- **Diseño**: Vanilla CSS/Flutter con estética premium de modo oscuro y micro-animaciones.

## ⚙️ Configuración

```bash
git clone https://github.com/dybrocorp/Zone.git
cd Zone
flutter pub get
flutter run
```

## 📜 Licencia y Desarrollador

Desarrollado con pasión por **Team Dybro** de **Dybro Corp**.
Todos los derechos reservados © 2026.
Para soporte, contactar a `support@dybrocorp.com`.
