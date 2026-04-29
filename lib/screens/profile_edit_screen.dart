import 'package:flutter/material.dart';
import '../services/zone_id_service.dart';
import '../services/permissions_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  _ProfileEditScreenState createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final ZoneIdService _zoneIdService = ZoneIdService();
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _igController = TextEditingController();
  final TextEditingController _fbController = TextEditingController();
  final TextEditingController _tiktokController = TextEditingController();
  
  bool _isIgVisible = true;
  bool _isFbVisible = true;
  bool _isTiktokVisible = true;
  bool _isStealthMode = false;
  bool _isLoading = true;
  File? _imageFile;
  String? _serverAvatarUrl;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _zoneIdService.getMyProfile();
      if (profile != null && mounted) {
        setState(() {
          _nameController.text = profile['display_name'] ?? '';
          _igController.text = profile['instagram_handle'] ?? '';
          _fbController.text = profile['facebook_handle'] ?? '';
          _tiktokController.text = profile['tiktok_handle'] ?? '';
          _isIgVisible = profile['ig_visible'] ?? true;
          _isFbVisible = profile['fb_visible'] ?? true;
          _isTiktokVisible = profile['tiktok_visible'] ?? true;
          _isStealthMode = profile['stealth_mode'] ?? false;
          _serverAvatarUrl = profile['avatar_url'];
        });
      }
    } catch (e) {
      print('[ProfileEditScreen] Error cargando perfil: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar perfil: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Solicitar permisos
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
  void dispose() {
    _nameController.dispose();
    _igController.dispose();
    _fbController.dispose();
    _tiktokController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      String? avatarUrl = _serverAvatarUrl;
      if (_imageFile != null) {
        avatarUrl = await _zoneIdService.uploadProfilePicture(_imageFile!);
      }

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

      await _zoneIdService.setStealthMode(_isStealthMode);

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado con éxito.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar cambios: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00D2FF))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Editar Mi Perfil'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Color(0xFF00D2FF)),
            onPressed: _saveProfile,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            GestureDetector(
              onTap: _showImageSourceActionSheet,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.black45,
                    backgroundImage: _imageFile != null 
                        ? FileImage(_imageFile!) 
                        : (_serverAvatarUrl != null ? NetworkImage(_serverAvatarUrl!) : null) as ImageProvider?,
                    child: _imageFile == null && _serverAvatarUrl == null
                        ? const Icon(Icons.person, size: 50, color: Colors.white54)
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF00D2FF),
                    ),
                    child: const Icon(Icons.edit, color: Colors.black, size: 20),
                  )
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _zoneIdService.zoneId ?? '',
              style: const TextStyle(color: Color(0xFF00D2FF), fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            _buildTextField(_nameController, 'Nombre público', Icons.badge),
            const SizedBox(height: 20),
            
            _buildSocialSwitch('Instagram', _igController, _isIgVisible, (v) => setState(() => _isIgVisible = v)),
            _buildSocialSwitch('Facebook', _fbController, _isFbVisible, (v) => setState(() => _isFbVisible = v)),
            _buildSocialSwitch('TikTok', _tiktokController, _isTiktokVisible, (v) => setState(() => _isTiktokVisible = v)),
            
            const Divider(color: Colors.white10, height: 40),
            
            SwitchListTile(
              title: const Text('Modo Timidez', style: TextStyle(color: Colors.white)),
              subtitle: const Text('No aparecerás en el radar de otros, pero tú si podrás verlos.', style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: _isStealthMode,
              activeColor: const Color(0xFF00D2FF),
              onChanged: (val) => setState(() => _isStealthMode = val),
            ),
            
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D2FF),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saveProfile,
              child: const Text('Guardar Cambios', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white54),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00D2FF))),
      ),
    );
  }

  Widget _buildSocialSwitch(String label, TextEditingController controller, bool isVisible, Function(bool) onToggle) {
    return Column(
      children: [
        _buildTextField(controller, label, Icons.alternate_email),
        SwitchListTile(
          title: Text('Visible en perfil', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          value: isVisible,
          activeColor: const Color(0xFF00D2FF),
          onChanged: onToggle,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
