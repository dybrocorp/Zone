import 'package:flutter/material.dart';

class PublicProfileSheet extends StatelessWidget {
  final String userId;
  final String userName;
  final bool hasInstagram;
  final bool hasFacebook;
  final bool hasTiktok;

  const PublicProfileSheet({
    super.key,
    required this.userId,
    required this.userName,
    this.hasInstagram = false,
    this.hasFacebook = false,
    this.hasTiktok = false,
  });

  static void show(BuildContext context, {
    required String userId,
    required String userName,
    bool hasInstagram = false,
    bool hasFacebook = false,
    bool hasTiktok = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PublicProfileSheet(
        userId: userId,
        userName: userName,
        hasInstagram: hasInstagram,
        hasFacebook: hasFacebook,
        hasTiktok: hasTiktok,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle superior para cerrar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 30),
          
          // Avatar y Nombre del Usuario
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey.shade800,
                child: const Icon(Icons.person, size: 40, color: Colors.white54),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${userId.substring(0, 8)}...',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          
          // Redes Sociales (solo se dibujan si el usuario dio el permiso de visibilidad)
          if (hasInstagram || hasFacebook || hasTiktok) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Redes Públicas', style: TextStyle(color: Colors.white70, fontSize: 16)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSocialIcon(Icons.camera_alt, 'Instagram', hasInstagram),
                _buildSocialIcon(Icons.facebook, 'Facebook', hasFacebook),
                _buildSocialIcon(Icons.music_note, 'TikTok', hasTiktok),
              ],
            ),
            const SizedBox(height: 40),
          ] else ...[
            const Text('Este usuario no ha compartido redes públicas.', style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
            const SizedBox(height: 30),
          ],
          
          // Botón de Conectar / Solicitar Chat E2EE
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D2FF),
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.lock, color: Colors.black, size: 20),
            label: const Text(
              'Solicitar Chat Privado E2EE',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            onPressed: () {
              Navigator.pop(context);
              // TODO: Lógica para insertar en latabla 'connection_requests' de Supabase
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Solicitud de conexión enviada. Esperando aceptación de la otra persona.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSocialIcon(IconData icon, String name, bool isVisible) {
    if (!isVisible) return const SizedBox.shrink();
    return Column(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: const Color(0xFF0F172A),
          child: Icon(icon, color: const Color(0xFF00D2FF)),
        ),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
