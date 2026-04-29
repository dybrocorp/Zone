import 'package:flutter/material.dart';
import '../services/zone_id_service.dart';
import 'radar_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final _zoneIdService = ZoneIdService();
  bool _isLoading = false;

  void _doLogin() async {
    final id = _idController.text.trim();
    if (id.isEmpty) return;

    setState(() => _isLoading = true);
    
    try {
      final success = await _zoneIdService.loginWithExistingID(id);
      
      if (!mounted) return;
      
      if (success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RadarScreen()),
        );
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ID de Zona no encontrado o inválido')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al ingresar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Iniciar Sesión'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fingerprint, size: 80, color: Color(0xFF00D2FF)),
            const SizedBox(height: 40),
            const Text(
              'Ingresa con tu ID de Zona',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _idController,
              style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 2),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'ZONE-XXXXXXXX',
                hintStyle: const TextStyle(color: Colors.white24),
                labelText: 'Tu ID Único',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00D2FF))),
                prefixIcon: const Icon(Icons.qr_code, color: Colors.white54),
              ),
            ),
            const SizedBox(height: 40),
            _isLoading
                ? const CircularProgressIndicator(color: Color(0xFF00D2FF))
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D2FF),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _doLogin,
                    child: const Text('Entrar a Mi Radar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
          ],
        ),
      ),
    );
  }
}
