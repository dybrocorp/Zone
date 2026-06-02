import 'package:flutter/material.dart';
import 'auth_screen.dart';
import '../services/zone_id_service.dart';
import '../services/permissions_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/supabase_service.dart';
import '../services/nearby_service.dart';

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
  bool _avatarIsPublic = true;
  bool _isLoading = true;
  File? _imageFile;
  String? _serverAvatarUrl;
  
  List<dynamic> _serverGalleryPhotos = [];
  List<File> _newGalleryFiles = [];
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
          _avatarIsPublic = profile['avatar_is_public'] ?? true;
          _serverGalleryPhotos = List<dynamic>.from(profile['gallery_photos'] ?? []);
        });
      }
    } catch (e) {
      print('[ProfileEditScreen] Error cargando perfil: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tus datos de perfil no se pudieron cargar. Es posible que debas configurarlos de nuevo debido a un error de seguridad en el almacenamiento de tu dispositivo.'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.orangeAccent,
          ),
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

  Future<void> _pickGalleryImage() async {
    try {
      await PermissionsService.requestCameraAndGalleryPermissions();
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _newGalleryFiles.add(File(pickedFile.path));
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar foto de galería: $e')),
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

      // Subir fotos de galería nuevas
      for (final file in _newGalleryFiles) {
        final url = await _zoneIdService.uploadProfilePicture(file);
        _serverGalleryPhotos.add({
          'url': url,
          'is_public': true // Por defecto público; se puede cambiar en la UI
        });
      }
      _newGalleryFiles.clear();

      await _zoneIdService.updateProfile(
        displayName: _nameController.text.trim(),
        instagram: _igController.text.trim().isNotEmpty ? _igController.text.trim() : null,
        igVisible: _isIgVisible,
        facebook: _fbController.text.trim().isNotEmpty ? _fbController.text.trim() : null,
        fbVisible: _isFbVisible,
        tiktok: _tiktokController.text.trim().isNotEmpty ? _tiktokController.text.trim() : null,
        tiktokVisible: _isTiktokVisible,
        avatarUrl: avatarUrl,
        avatarIsPublic: _avatarIsPublic,
        galleryPhotos: _serverGalleryPhotos.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );

      await _zoneIdService.setStealthMode(_isStealthMode);
      
      // Actualizar Modo Timidez en el radar inmediatamente
      final currentUid = _zoneIdService.uid;
      if (currentUid != null) {
        await NearbyService().initialize(currentUid);
        if (NearbyService().isRadarActive) {
          await NearbyService().stopRadar();
          await NearbyService().startRadar();
        }
      }

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

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Se borrarán tus datos locales. Necesitarás tu ZONE-ID para volver a entrar en este u otro dispositivo.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CERRAR SESIÓN', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _zoneIdService.clearAuth();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('¡ATENCIÓN!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Estás a punto de eliminar tu perfil definitivamente de toda la base de datos, tanto de la nube como de esta aplicación.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Esta acción borrará tus mensajes, fotos, encuentros y tu cuenta de acceso de forma IRREVERSIBLE.',
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 12),
            Text(
              '¿Deseas proceder con el borrado total?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ELIMINAR TODO', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _showLoadingOverlay();
      try {
        await _zoneIdService.deleteAccount();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => AuthScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading overlay
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar cuenta: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  void _showLoadingOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00D2FF)),
      ),
    );
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
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Hacer avatar público', style: TextStyle(color: Colors.white, fontSize: 13)),
              value: _avatarIsPublic,
              activeColor: const Color(0xFF00D2FF),
              onChanged: (val) => setState(() => _avatarIsPublic = val),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 15),
            _buildGallery(),
            const SizedBox(height: 30),
            _buildTextField(_nameController, 'Nombre público', Icons.badge),
            const SizedBox(height: 20),
            
            _buildSocialSwitch('Instagram', _igController, _isIgVisible, (v) => setState(() => _isIgVisible = v)),
            _buildSocialSwitch('Facebook', _fbController, _isFbVisible, (v) => setState(() => _isFbVisible = v)),
            _buildSocialSwitch('TikTok', _tiktokController, _isTiktokVisible, (v) => setState(() => _isTiktokVisible = v)),
            
            const Divider(color: Colors.white10, height: 40),
            
            SwitchListTile(
              title: const Text('Modo Timidez', style: TextStyle(color: Colors.white)),
              subtitle: const Text('No aparecerás en el radar de otros, pero podrás seguir buscando.', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
            ),
            
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              label: const Text('Cerrar Sesión', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _confirmDeleteAccount,
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              label: const Text('Eliminar Perfil Definitivamente', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
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

  Widget _buildGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Galería Privada / Pública', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap: _pickGalleryImage,
                child: Container(
                  width: 100,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00D2FF), width: 1, style: BorderStyle.solid),
                  ),
                  child: const Center(child: Icon(Icons.add_a_photo, color: Color(0xFF00D2FF), size: 30)),
                ),
              ),
              ..._serverGalleryPhotos.map((photo) {
                final isPublic = photo['is_public'] ?? true;
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(image: NetworkImage(photo['url']), fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      bottom: 4, right: 16,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => photo['is_public'] = !isPublic);
                        },
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black87,
                          child: Icon(isPublic ? Icons.public : Icons.lock, color: isPublic ? Color(0xFF00D2FF) : Colors.redAccent, size: 16),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4, right: 16,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _serverGalleryPhotos.remove(photo));
                        },
                        child: const CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black87,
                          child: Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              ..._newGalleryFiles.map((file) {
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      bottom: 4, right: 16,
                      child: const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.black87,
                        child: Icon(Icons.cloud_upload, color: Colors.orangeAccent, size: 16),
                      ),
                    ),
                    Positioned(
                      top: 4, right: 16,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _newGalleryFiles.remove(file));
                        },
                        child: const CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black87,
                          child: Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
