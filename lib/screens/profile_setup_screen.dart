import 'package:flutter/material.dart';
import 'radar_screen.dart';
import '../services/zone_id_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String generatedId;
  const ProfileSetupScreen({super.key, required this.generatedId});

  @override
  _ProfileSetupScreenState createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _igController = TextEditingController();
  final TextEditingController _fbController = TextEditingController();
  final TextEditingController _tiktokController = TextEditingController();

  bool _isIgVisible = true;
  bool _isFbVisible = true;
  bool _isTiktokVisible = true;
  bool _isSaving = false;

  final _zoneIdService = ZoneIdService();

  void _finishSetup() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pon un nombre o apodo para continuar')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Guardar perfil en Supabase
      await _zoneIdService.updateProfile(
        displayName: _nameController.text.trim(),
        instagram: _igController.text.trim().isNotEmpty ? _igController.text.trim() : null,
        igVisible: _isIgVisible,
        facebook: _fbController.text.trim().isNotEmpty ? _fbController.text.trim() : null,
        fbVisible: _isFbVisible,
        tiktok: _tiktokController.text.trim().isNotEmpty ? _tiktokController.text.trim() : null,
        tiktokVisible: _isTiktokVisible,
      );
    } catch (e) {
      // Log y continuar aunque falle
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RadarScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Configura tu Perfil'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 55,
                          backgroundColor: Colors.grey.shade800,
                          child: const Icon(Icons.person, size: 60, color: Colors.white54),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF00D2FF),
                          ),
                          child: const Icon(Icons.camera_alt, color: Colors.black, size: 22),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.generatedId,
                      style: const TextStyle(
                        color: Color(0xFF00D2FF),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tu ID único y privado — nunca cambia',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nombre / Apodo *',
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00D2FF))),
                  prefixIcon: const Icon(Icons.badge, color: Colors.white54),
                ),
              ),
              const SizedBox(height: 30),
              const Text('Redes Sociales (Opcional)', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Tú controlas qué se muestra cuando alguien te escanea.', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 20),

              _buildSocialField('Instagram', _igController, _isIgVisible, (val) => setState(() => _isIgVisible = val)),
              _buildSocialField('Facebook', _fbController, _isFbVisible, (val) => setState(() => _isFbVisible = val)),
              _buildSocialField('TikTok', _tiktokController, _isTiktokVisible, (val) => setState(() => _isTiktokVisible = val)),

              const SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2FF),
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSaving ? null : _finishSetup,
                child: _isSaving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Entrar a Zone', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialField(String name, TextEditingController controller, bool isVisible, Function(bool) onToggle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        children: [
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Usuario en $name',
              labelStyle: const TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00D2FF))),
              prefixIcon: const Icon(Icons.alternate_email, color: Colors.white54),
            ),
          ),
          SwitchListTile(
            title: const Text('Visible en tu perfil público', style: TextStyle(color: Colors.white70, fontSize: 13)),
            value: isVisible,
            activeThumbColor: const Color(0xFF00D2FF),
            onChanged: onToggle,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
