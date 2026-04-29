import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'blocked_users_screen.dart';
import '../services/zone_id_service.dart';
import 'auth_screen.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _zoneIdService = ZoneIdService();
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
        });
      }
    } catch (e) {
      // Ignorar si falla
    }
  }

  void _showDocument(String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  content,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Líneas de Atención', style: TextStyle(color: Colors.white)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Soporte Técnico:', style: TextStyle(color: Color(0xFF00D2FF), fontWeight: FontWeight.bold)),
            Text('support@dybrocorp.com', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 16),
            Text('Reportes de Seguridad:', style: TextStyle(color: Color(0xFF00D2FF), fontWeight: FontWeight.bold)),
            Text('security@zoneapp.com', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 16),
            Text('GitHub / Dybro Corp:', style: TextStyle(color: Color(0xFF00D2FF), fontWeight: FontWeight.bold)),
            Text('github.com/dybrocorp', style: TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR', style: TextStyle(color: Color(0xFF00D2FF)))),
        ],
      ),
    );
  }

  void _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.white)),
        content: const Text('Se borrarán tus datos locales. Necesitarás tu ZONE-ID para volver a entrar en este u otro dispositivo.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('CERRAR SESIÓN', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirm == true) {
      // Nota: En una app real de E2EE, deberías exportar tu clave privada antes de borrar.
      // Aquí simplemente limpiamos la sesión local para el demo.
      // Implementamos una función de logout en ZoneIdService si hace falta.
      // Por ahora limpiamos storage.
      await _zoneIdService.clearAuth();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Ajustes'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('INFORMACIÓN'),
          _buildTile(
            icon: Icons.info_outline,
            title: 'Sobre Zone',
            subtitle: 'Versión $_appVersion • Dybro Corp',
            onTap: () {
              _showDocument(
                'Sobre Zone', 
                'Zone nació de la necesidad de crear conexiones humanas reales y seguras en un mundo digital sobreexplotado. \n\n'
                'Inspirado en la simplicidad de compartir momentos y la potencia de la criptografía, Zone permite descubrir a quienes te rodean mediante Bluetooth Low Energy, garantizando que tu identidad sea siempre un código anónimo controlado por ti.\n\n'
                'Creado por Dybro Corp para aquellos que valoran su privacidad tanto como su vida social.\n\n'
                'Versión: $_appVersion\n'
                'Desarrollado por: Team Dybro\n'
                'Año: 2026'
              );
            },
          ),
          _buildTile(
            icon: Icons.help_outline,
            title: 'Líneas de Atención',
            onTap: _showSupportDialog,
          ),
          
          const SizedBox(height: 24),
          _buildSectionHeader('PRIVACIDAD'),
          _buildTile(
            icon: Icons.block,
            title: 'Contactos Bloqueados',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlockedUsersScreen()));
            },
          ),
          _buildTile(
            icon: Icons.description_outlined,
            title: 'Términos y Condiciones',
            onTap: () => _showDocument('Términos y Condiciones', _termsContent),
          ),
          _buildTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Política de Privacidad',
            onTap: () => _showDocument('Política de Privacidad', _privacyContent),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('CUENTA'),
          _buildTile(
            icon: Icons.logout,
            title: 'Cerrar Sesión',
            textColor: Colors.redAccent,
            onTap: _signOut,
          ),
          
          const SizedBox(height: 60),
          const Center(
            child: Text(
              'DYBRO CORP • 2026',
              style: TextStyle(color: Colors.white24, letterSpacing: 2, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(color: Color(0xFF00D2FF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildTile({required IconData icon, required String title, String? subtitle, VoidCallback? onTap, Color? textColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: textColor ?? Colors.white70),
        title: Text(title, style: TextStyle(color: textColor ?? Colors.white, fontWeight: FontWeight.w500)),
        subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)) : null,
        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
        onTap: onTap,
      ),
    );
  }

  // Contenido estático (podría leerse de archivos, pero para velocidad del demo lo incluyo aquí simplificado)
  final String _termsContent = '''
# Términos y Condiciones
Última actualización: Abril 2026

1. Aceptación de los Términos
Al acceder o utilizar Zone, desarrollado por Dybro Corp, usted acepta estar sujeto a estos Términos y Condiciones.

2. Propósito del Servicio
Zone es una red social basada en proximidad (Bluetooth) y privacidad con cifrado de extremo a extremo (E2EE).

3. Responsabilidad del Usuario
- Usted es responsable de la información que decide compartir.
- Se prohíbe el uso de Zone para acoso o actividades ilícitas.

4. Seguridad
Zone usa claves X25519 y ChaCha20-Poly1305 para proteger todas las comunicaciones. No tenemos acceso a sus mensajes privados.

5. Propiedad Intelectual
Todos los derechos son de Dybro Corp.

6. Limitación de Responsabilidad
Dybro Corp no se hace responsable por encuentros en la vida real derivados del uso de la app. Al ser una red descentralizada y anónima, Zone no garantiza la identidad verídica de los perfiles encontrados.
''';

  final String _privacyContent = '''
# Políticas de Privacidad
Última actualización: Abril 2026

1. Información que Recopilamos
- No usamos correos ni números de teléfono.
- Datos de Proximidad: Usamos Bluetooth (BLE) para detectar usuarios cercanos de forma anónima.
- Mensajes: Cifrados de extremo a extremo (E2EE). Las claves nunca salen de su dispositivo.

2. Uso de la Información
El uso del Bluetooth es exclusivo para la funcionalidad del radar.

3. Divulgación a Terceros
No vendemos ni compartimos sus datos con nadie.

4. Retención de Datos
Usted puede eliminar su perfil desde la app en cualquier momento, borrando sus credenciales del servidor.

5. Sus Derechos
Usted tiene control total sobre su visibilidad y enlaces de redes sociales.
''';
}
