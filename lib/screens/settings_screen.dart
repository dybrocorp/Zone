import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'blocked_users_screen.dart';
import '../config/radar_config.dart';
import '../services/nearby_service.dart';
import '../services/premium_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nearbyService = NearbyService();
  String _appVersion = '1.0.0';
  double _discoveryRadius = RadarConfig.discoveryRadiusMeters;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
    _loadRadarRadius();
  }

  Future<void> _loadRadarRadius() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(RadarConfig.prefsDiscoveryRadiusKey);
    final isPremium = await PremiumService.instance.loadPremiumStatus();
    if (mounted) {
      setState(() {
        _isPremium = isPremium;
        _discoveryRadius = RadarConfig.effectiveRadius(saved, isPremium: isPremium);
      });
    }
  }

  void _showPremiumRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('Zone Premium', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Ampliar el radar a más de 20 metros está disponible solo con Zone Premium. '
          'Activa Premium desde la tienda de la app para detectar usuarios hasta 30 m.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ENTENDIDO', style: TextStyle(color: Color(0xFF00D2FF))),
          ),
        ],
      ),
    );
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
            Text('contacto@dybrocorp.com', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 16),
            Text('Asuntos Legales / Privacidad:', style: TextStyle(color: Color(0xFF00D2FF), fontWeight: FontWeight.bold)),
            Text('legal@dybrocorp.com', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 16),
            Text('GitHub / DYBROCORP:', style: TextStyle(color: Color(0xFF00D2FF), fontWeight: FontWeight.bold)),
            Text('github.com/dybrocorp', style: TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR', style: TextStyle(color: Color(0xFF00D2FF)))),
        ],
      ),
    );
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
            subtitle: 'Versión $_appVersion • DYBROCORP',
            onTap: () {
              _showDocument(
                'Sobre Zone', 
                'Zone nació de la necesidad de crear conexiones humanas reales y seguras en un mundo digital sobreexplotado. \n\n'
                'Inspirado en la simplicidad de compartir momentos y la potencia de la criptografía, Zone permite descubrir a quienes te rodean mediante Bluetooth Low Energy, garantizando que tu identidad sea siempre un código anónimo controlado por ti.\n\n'
                'Creado por DYBROCORP para aquellos que valoran su privacidad tanto como su vida social.\n\n'
                'Versión: $_appVersion\n'
                'Desarrollado por: DYBROCORP\n'
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
          _buildSectionHeader('RADAR BLUETOOTH'),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.radar, color: Colors.white70),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Radio de detección: ${_discoveryRadius.round()} m',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _isPremium
                      ? 'Usuarios Zone dentro de este radio (hasta 30 m con Premium).'
                      : 'Hasta 20 m en versión gratuita. Más de 20 m requiere Zone Premium.',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                if (!_isPremium)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(Icons.lock, size: 14, color: Colors.amber.shade200),
                        const SizedBox(width: 6),
                        Text(
                          '25–30 m bloqueados',
                          style: TextStyle(color: Colors.amber.shade200, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                Slider(
                  value: _discoveryRadius,
                  min: RadarConfig.minDiscoveryRadiusMeters,
                  max: RadarConfig.sliderMax(isPremium: _isPremium),
                  divisions: 5,
                  activeColor: const Color(0xFF00D2FF),
                  label: '${_discoveryRadius.round()} m',
                  onChanged: (v) {
                    if (!_isPremium && v > RadarConfig.maxFreeDiscoveryRadiusMeters) {
                      _showPremiumRequiredDialog();
                      return;
                    }
                    setState(() => _discoveryRadius = v);
                  },
                  onChangeEnd: (v) async {
                    if (!_isPremium && v > RadarConfig.maxFreeDiscoveryRadiusMeters) {
                      setState(() => _discoveryRadius = RadarConfig.maxFreeDiscoveryRadiusMeters);
                      _showPremiumRequiredDialog();
                      await _nearbyService.setDiscoveryRadiusMeters(RadarConfig.maxFreeDiscoveryRadiusMeters);
                      return;
                    }
                    await _nearbyService.setDiscoveryRadiusMeters(v);
                  },
                ),
              ],
            ),
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
          _buildSectionHeader('MODO DESARROLLADOR'),
          _buildTile(
            icon: Icons.speed,
            title: 'Prueba de Estrés Mesh',
            subtitle: 'Simula 50 mensajes entrantes en la malla',
            onTap: () {
              _nearbyService.simulateMeshTraffic(50);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Simulación de red mesh iniciada (50 nodos)')),
              );
            },
          ),

          const SizedBox(height: 60),
          Center(
            child: Opacity(
              opacity: 0.5,
              child: Image.asset(
                'assets/dybrocorp_banner.png',
                width: 250,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'DYBRO CORP • 2026',
              style: TextStyle(color: Colors.white24, letterSpacing: 2, fontSize: 10),
            ),
          ),
          const SizedBox(height: 40),
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

  // Contenido oficial de DYBROCORP 2026
  final String _termsContent = '''
# Términos y Condiciones - DYBROCORP / ZONE
Versión 1.0 (Mayo 2026)

1. Introducción
Estos términos regulan el uso de ZONE y productos de DYBROCORP. El uso de la app implica su aceptación expresa.

2. Identificación
DYBROCORP, con sede principal en la República de Colombia. Contacto: contacto@dybrocorp.com.

3. Capacidad Legal
El usuario declara tener capacidad legal y suministrar información veraz.

4. Responsabilidad
El usuario es responsable de sus credenciales y de toda actividad realizada desde su cuenta.

5. Uso Permitido
Se prohíbe el uso para actividades ilícitas, acoso, malware, suplantación o scraping.

6. Propiedad Intelectual
Todo el software, logos y algoritmos son propiedad de DYBROCORP. Queda prohibida la ingeniería inversa o reproducción no autorizada.

7. Limitación de Responsabilidad
DYBROCORP no se hace responsable por encuentros en la vida real. Los usuarios interactúan bajo su propio riesgo.

8. Modificaciones
Podremos modificar estos términos en cualquier momento, entrando en vigencia desde su publicación en la app.
''';

  final String _privacyContent = '''
# Política de Privacidad - DYBROCORP / ZONE
Versión 1.0 (Mayo 2026)

1. Responsable
DYBROCORP es el responsable del tratamiento de sus datos personales.

2. Información Recopilada
- Datos técnicos (IP, dispositivo).
- ZONE-ID y datos de perfil.
- Mensajes cifrados de extremo a extremo (E2EE) que nunca abandonan su dispositivo en texto plano.

3. Finalidades
Operar el servicio, mejorar la experiencia y garantizar la seguridad mediante tecnología de proximidad Bluetooth (BLE).

4. Derechos del Titular
Usted tiene derecho a conocer, actualizar y rectificar sus datos personales enviando un correo a legal@dybrocorp.com.

5. Seguridad Digital
Implementamos medidas alineadas con ISO/IEC 27001 y OWASP para proteger su infraestructura y privacidad.

6. No Venta de Datos
DYBROCORP NO vende su información personal a terceros.

7. Conservación
Los datos se conservan mientras exista la relación o por obligación legal.
''';
}
