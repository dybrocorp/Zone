import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'mock_chat_screen.dart';
import '../services/mock_chat_service.dart';

class PublicProfileSheet extends StatefulWidget {
  final String userId;
  final String userName;
  final String? instagramHandle;
  final String? facebookHandle;
  final String? tiktokHandle;
  final String? avatarUrl;

  const PublicProfileSheet({
    super.key,
    required this.userId,
    required this.userName,
    this.instagramHandle,
    this.facebookHandle,
    this.tiktokHandle,
    this.avatarUrl,
  });

  static void show(BuildContext context, {
    required String userId,
    required String userName,
    String? instagramHandle,
    String? facebookHandle,
    String? tiktokHandle,
    String? avatarUrl,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PublicProfileSheet(
        userId: userId,
        userName: userName,
        instagramHandle: instagramHandle,
        facebookHandle: facebookHandle,
        tiktokHandle: tiktokHandle,
        avatarUrl: avatarUrl,
      ),
    );
  }

  @override
  State<PublicProfileSheet> createState() => _PublicProfileSheetState();
}

class _PublicProfileSheetState extends State<PublicProfileSheet> {
  // 0: Initial, 1: Requesting, 2: Approved
  int _connectionState = 0;

  Future<void> _launchUrl(String platform, String? handle) async {
    if (handle == null || handle.isEmpty) return;
    
    String url = '';
    String sanitizedHandle = handle.replaceAll('@', '');
    
    if (platform == 'Instagram') {
      url = 'https://instagram.com/$sanitizedHandle';
    } else if (platform == 'Facebook') {
      url = 'https://facebook.com/$sanitizedHandle';
    } else if (platform == 'TikTok') {
      url = 'https://tiktok.com/@$sanitizedHandle';
    }

    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir $url')),
        );
      }
    }
  }

  void _handleConnectPressed() async {
    if (_connectionState == 0) {
      setState(() => _connectionState = 1);
      
      // Simular retraso de red
      await Future.delayed(const Duration(milliseconds: 1500));
      
      if (!mounted) return;
      
      // Auto aprueba siempre para facilitar las pruebas
      setState(() => _connectionState = 2);
    } else if (_connectionState == 2) {
      // Activar chat mock para que aparezca en la bandeja
      await MockChatService().activateMockChat(
        widget.userId, 
        widget.userName, 
        widget.avatarUrl
      );

      if (!mounted) return;
      Navigator.pop(context); // Cierra el bottom sheet
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MockChatScreen(
            botName: widget.userName,
            zoneId: widget.userId,
            avatarUrl: widget.avatarUrl,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasIg = widget.instagramHandle != null && widget.instagramHandle!.isNotEmpty;
    final hasFb = widget.facebookHandle != null && widget.facebookHandle!.isNotEmpty;
    final hasTiktok = widget.tiktokHandle != null && widget.tiktokHandle!.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 30),
          
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey.shade800,
                backgroundImage: widget.avatarUrl != null ? NetworkImage(widget.avatarUrl!) : null,
                child: widget.avatarUrl == null
                    ? Text(
                        widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white54),
                      )
                    : null,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.userName,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${widget.userId.substring(0, 8)}...',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          
          if (hasIg || hasFb || hasTiktok) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Redes Públicas', style: TextStyle(color: Colors.white70, fontSize: 16)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSocialIcon(Icons.camera_alt, 'Instagram', hasIg, () => _launchUrl('Instagram', widget.instagramHandle)),
                _buildSocialIcon(Icons.facebook, 'Facebook', hasFb, () => _launchUrl('Facebook', widget.facebookHandle)),
                _buildSocialIcon(Icons.music_note, 'TikTok', hasTiktok, () => _launchUrl('TikTok', widget.tiktokHandle)),
              ],
            ),
            const SizedBox(height: 40),
          ] else ...[
            const Text('Este usuario no ha compartido redes públicas.', style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
            const SizedBox(height: 30),
          ],
          
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _connectionState == 0 ? const Color(0xFF00D2FF) : (_connectionState == 1 ? Colors.grey.shade600 : Colors.greenAccent),
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _connectionState == 1 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Icon(Icons.lock, color: _connectionState == 1 ? Colors.white : Colors.black, size: 20),
            label: Text(
              _connectionState == 0 
                ? 'Solicitar Chat Privado E2EE' 
                : (_connectionState == 1 ? 'Esperando aprobación...' : '¡Chat Aprobado! (Entrar)'),
              style: TextStyle(
                color: _connectionState == 1 ? Colors.white : Colors.black, 
                fontWeight: FontWeight.bold, 
                fontSize: 16
              ),
            ),
            onPressed: (_connectionState == 1) ? null : _handleConnectPressed,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSocialIcon(IconData icon, String name, bool isVisible, VoidCallback onTap) {
    if (!isVisible) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: const Color(0xFF0F172A),
            child: Icon(icon, color: const Color(0xFF00D2FF)),
          ),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}
