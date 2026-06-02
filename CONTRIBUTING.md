# Contributing to Zone / Contribuyendo a Zone

## 🇬🇧 English Version

Thank you for your interest in contributing to Zone! This document provides guidelines and instructions for contributing.

### Code of Conduct

Please be respectful and constructive in all interactions. We are committed to providing a welcoming and inclusive environment for all contributors.

### Reporting Issues

#### Security Issues
**Do not open a public issue for security vulnerabilities.** See [SECURITY.md](SECURITY.md) for responsible disclosure.

#### Bug Reports
When reporting bugs, please include:
- Device/OS information and Flutter version
- Zone app version
- Steps to reproduce the issue
- Expected vs actual behavior
- Error logs or screenshots (if applicable)
- Bluetooth device information (if BLE-related)

#### Feature Requests
Describe the feature, explain the use case, and why it would be beneficial to Zone users.

### Development Setup

#### Prerequisites
- Flutter SDK: 3.10.8+
- Dart: 3.10.8+
- Android SDK (for Android development)
- Xcode 14+ (for iOS development)
- Git

#### Getting Started
```bash
# Clone the repository
git clone https://github.com/dybrocorp/Zone.git
cd Zone

# Get dependencies
flutter pub get

# Run the app
flutter run
```

### Code Style

- Follow [Dart conventions](https://dart.dev/guides/language/effective-dart/style)
- Use `flutter format .` before committing
- Use `flutter analyze` to check for issues
- Keep commits atomic and descriptive

### Pull Request Process

1. **Fork the repository** and create a feature branch
2. **Make your changes** with clear, atomic commits
3. **Test thoroughly** before submitting
4. **Push to your fork** and submit a Pull Request

### Security Best Practices

- **Never commit secrets** - API keys, tokens, passwords
- Use `.gitignore` to exclude sensitive files (already configured)
- Review cryptographic implementations carefully
- See [SECURITY_BEST_PRACTICES.md](SECURITY_BEST_PRACTICES.md)

### Testing

```bash
flutter test
flutter test --coverage
flutter analyze
```

### Community

- 💬 [Discussions](https://github.com/dybrocorp/Zone/discussions)
- 🐛 [Issues](https://github.com/dybrocorp/Zone/issues)
- 📧 Email: dev@dybrocorp.com

---

## 🇪🇸 Versión en Español

¡Gracias por tu interés en contribuir a Zone! Este documento proporciona pautas e instrucciones para contribuir.

### Código de Conducta

Por favor, sé respetuoso y constructivo en todas las interacciones. Estamos comprometidos a proporcionar un entorno acogedor e inclusivo para todos los colaboradores.

### Reportar Problemas

#### Problemas de Seguridad
**No abras un issue público para vulnerabilidades de seguridad.** Consulta [SECURITY.md](SECURITY.md) para divulgación responsable.

#### Reportes de Bugs
Cuando reportes bugs, incluye:
- Información del dispositivo/OS y versión de Flutter
- Versión de la aplicación Zone
- Pasos para reproducir el problema
- Comportamiento esperado vs actual
- Logs de error o capturas (si aplica)
- Información del dispositivo Bluetooth (si está relacionado con BLE)

#### Solicitudes de Características
Describe la característica, explica el caso de uso y por qué sería beneficioso para los usuarios de Zone.

### Configuración del Desarrollo

#### Requisitos Previos
- Flutter SDK: 3.10.8+
- Dart: 3.10.8+
- Android SDK (para desarrollo en Android)
- Xcode 14+ (para desarrollo en iOS)
- Git

#### Comenzar
```bash
# Clonar el repositorio
git clone https://github.com/dybrocorp/Zone.git
cd Zone

# Obtener dependencias
flutter pub get

# Ejecutar la aplicación
flutter run
```

### Estilo de Código

- Sigue [las convenciones de Dart](https://dart.dev/guides/language/effective-dart/style)
- Usa `flutter format .` antes de hacer commit
- Usa `flutter analyze` para verificar problemas
- Mantén commits atómicos y descriptivos

### Proceso de Pull Request

1. **Fork el repositorio** y crea una rama de características
2. **Realiza cambios** con commits claros y atómicos
3. **Prueba a fondo** antes de enviar
4. **Sube a tu fork** y envía un Pull Request

### Mejores Prácticas de Seguridad

- **Nunca hagas commit con secretos** - API keys, tokens, contraseñas
- Usa `.gitignore` para excluir archivos sensibles (ya configurado)
- Revisa cuidadosamente implementaciones criptográficas
- Consulta [SECURITY_BEST_PRACTICES.md](SECURITY_BEST_PRACTICES.md)

### Pruebas

```bash
flutter test
flutter test --coverage
flutter analyze
```

### Comunidad

- 💬 [Discusiones](https://github.com/dybrocorp/Zone/discussions)
- 🐛 [Issues](https://github.com/dybrocorp/Zone/issues)
- 📧 Email: dev@dybrocorp.com

---

Thank you for making Zone better! / ¡Gracias por mejorar Zone! 🚀

**Last Updated / Última Actualización**: 2026-05-29
