import 'package:flutter/material.dart';
import 'radar_screen.dart';
import '../services/zone_id_service.dart';
import '../services/permissions_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

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
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

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
      String? avatarUrl;
      
      // 1. Subir imagen si seleccionó una
      if (_imageFile != null) {
        avatarUrl = await _zoneIdService.uploadProfilePicture(_imageFile!);
      }

      // 2. Guardar perfil en Supabase
      await _zoneIdService.updateProfile(
        displayName: _nameController.text.trim(),
        instagram: _igController.text.trim().isNotEmpty ? _igController.text.trim() : null,
        igVisible: _isIgVisible,
        facebook: _fbController.text.trim().isNotEmpty ? _fbController.text.trim() : null,
        fbVisible: _isFbVisible,
        tiktok: _tiktokController.text.trim().isNotEmpty ? _tiktokController.text.trim() : null,
        tiktokVisible: _isTiktokVisible,
        avatarUrl: avatarUrl,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RadarScreen()),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar perfil: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Solicitar permisos antes de intentar abrir cámara/galería
      await PermissionsService.requestCameraAndGalleryPermissions();

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar imagen: $e')),
      );
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF00D2FF)),
              title: const Text('Cámara', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF00D2FF)),
              title: const Text('Galería', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
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
                    GestureDetector(
                      onTap: _showImageSourceActionSheet,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 55,
                            backgroundColor: Colors.grey.shade800,
                            backgroundImage: _imageFile != null ? FileImage(_imageFile!) : null,
                            child: _imageFile == null
                                ? const Icon(Icons.person, size: 60, color: Colors.white54)
                                : null,
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
                    : const Text('Comenzar tu registro', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
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
