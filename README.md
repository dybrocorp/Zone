# Zone - Proximity Social Network

**Descubre a quienes te rodean, sin perder tu privacidad.**

[![Descargar APK](https://img.shields.io/badge/Descargar-Zone%20APK-00D2FF?style=for-the-badge&logo=android)](https://github.com/dybrocorp/Zone/raw/main/Zone.apk)

Zone es una plataforma de red social revolucionaria basada en la proximidad física (vía Bluetooth Low Energy) y el anonimato total. Diseñada con una estética moderna "ShareIt style", Zone te permite detectar personas en tu "radar" local, establecer conexiones seguras y chatear mediante un protocolo de cifrado de extremo a extremo (E2EE) de grado industrial.

---

## 🏢 DybroCorp

Zone es un producto propiedad de **DybroCorp**, una compañía tecnológica líder enfocada en el desarrollo de ecosistemas digitales, ciberseguridad y transformación digital.

### Misión
Diseñar y operar productos tecnológicos propios como **Zone** y **NovaApp**, ofreciendo experiencias modernas, escalables y confiables para usuarios, empresas y comunidades, bajo principios de protección de datos y cumplimiento normativo.

### Visión
Consolidar a DybroCorp como una compañía tecnológica líder en Latinoamérica y con proyección internacional, reconocida por el desarrollo de plataformas digitales innovadoras, seguras y de alto impacto.

---

## 🚀 Características Principales

- **Radar de Proximidad (BLE)**: Descubrimiento pasivo de usuarios cercanos sin necesidad de GPS, protegiendo tu ubicación exacta.
- **Privacidad Radical**: Sin correos, sin números de teléfono. Todo se basa en tu **ZONE-ID** único y claves criptográficas locales.
- **Mensajería E2EE**: Comunicación protegida por **X25519** (intercambio de claves) y **ChaCha20-Poly1305** (cifrado de mensajes).
- **Social Connect**: Comparte tus perfiles de Instagram, Facebook o TikTok de forma selectiva. Tú decides quién ve qué.
- **Modo Timidez (Stealth)**: Mira quién está cerca sin ser detectado en el radar de los demás.
- **Seguridad Corporativa**: Respaldado por los estándares de seguridad de Dybrocorp, incluyendo cifrado avanzado y monitoreo de integridad.

## 🛠️ Stack Tecnológico

- **Framework**: Flutter (Dart)
- **Backend**: Supabase (PostgreSQL, Realtime, Storage)
- **Seguridad**: Ed25519 para firmas, X25519 para E2EE, PBKDF2 para derivación de claves locales.
- **Diseño**: Estética premium de modo oscuro y micro-animaciones.

## ⚖️ Legal y Privacidad

El uso de esta plataforma está sujeto a los siguientes documentos legales de DYBROCORP:

- [Términos y Condiciones](TERMS.md)
- [Política de Privacidad](PRIVACY_POLICY.md)
- [Seguridad Digital](PRIVACY_POLICY.md#5-política-de-seguridad-digital)

## ⚙️ Instalación y Uso

```bash
git clone https://github.com/dybrocorp/Zone.git
cd Zone
flutter pub get
flutter run
```

---

Desarrollado con excelencia por **DybroCorp**.
Todos los derechos reservados © 2026.
Contacto Legal: `legal@dybrocorp.com` | Soporte: `contacto@dybrocorp.com`
