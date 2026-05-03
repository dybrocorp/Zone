import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';
import 'mock_chat_screen.dart';
import '../services/supabase_service.dart';
import '../services/zone_id_service.dart';
import '../services/mock_chat_service.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({Key? key}) : super(key: key);

  @override
  _ChatsListScreenState createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _supabaseService = SupabaseService();
  final _zoneIdService = ZoneIdService();
  final _mockChatService = MockChatService();
  
  List<Map<String, dynamic>> _matches = [];
  List<Map<String, dynamic>> _mockChats = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  Set<String> _mutedMatchIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final uid = _zoneIdService.uid;
      if (uid == null) {
        // Si no hay UID, intentamos restaurar sesión
        await _zoneIdService.getOrCreate();
      }
      
      final currentUid = _zoneIdService.uid;
      if (currentUid == null) return;

      final matches = await _supabaseService.getAcceptedMatches(currentUid);
      final pending = await _supabaseService.getPendingRequests(currentUid);
      final mockChats = await _mockChatService.getActiveMockChats();
      
      // Cargar bloqueados para filtrar
      final blocked = await _supabaseService.getBlockedUsers(currentUid);
      final blockedIds = blocked.map((b) => b['blocked_id'] as String).toSet();

      // Cargar silenciados localmente
      final prefs = await SharedPreferences.getInstance();
      final mutedList = prefs.getStringList('muted_chats') ?? [];

      if (mounted) {
        setState(() {
          // Filtrar matches que involucren a alguien bloqueado
          _matches = matches.where((m) {
            final otherId = m['requester_id'] == currentUid ? m['receiver_id'] : m['requester_id'];
            return !blockedIds.contains(otherId);
          }).toList();
          
          // También filtrar bots bloqueados (si aplicara)
          _mockChats = mockChats.where((c) => !blockedIds.contains(c['zoneId'])).toList();
          
          _pendingRequests = pending;
          _mutedMatchIds = mutedList.toSet();
        });
      }
    } catch (e) {
      print('[ChatsListScreen] Error cargando chats: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar mensajes: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Bandeja de Mensajes Seguros'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2FF)))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_pendingRequests.isNotEmpty) ...[
                    const Text('Solicitudes Pendientes', style: TextStyle(color: Color(0xFF00D2FF), fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    ..._pendingRequests.map((req) => _buildPendingItem(req)),
                    const Divider(color: Colors.white10, height: 40),
                  ],
                  const Text('Tus Chats', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  if (_matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('Aún no tienes chats activos.\nConéctate con alguien en el Radar.',
                            textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)),
                      ),
                    )
                  else
                    ..._matches.map((match) => _buildMatchItem(match)),
                  
                  if (_mockChats.isNotEmpty) ...[
                    const Divider(color: Colors.white10, height: 40),
                    const Text('Simulaciones (Bots)', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 12),
                    ..._mockChats.map((chat) => _buildMockChatItem(chat)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildMockChatItem(Map<String, dynamic> chat) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.white12,
        backgroundImage: chat['avatarUrl'] != null ? NetworkImage(chat['avatarUrl']) : null,
        child: chat['avatarUrl'] == null ? const Icon(Icons.smart_toy_outlined, color: Colors.white70) : null,
      ),
      title: Text(chat['name'] ?? 'Bot', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(chat['lastMessage'] ?? 'E2EE Simulado', style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MockChatScreen(
              botName: chat['name'],
              zoneId: chat['zoneId'],
              avatarUrl: chat['avatarUrl'],
            ),
          ),
        );
        _loadData(); // Refrescar último mensaje al volver
      },
      onLongPress: () => _showChatOptions(chat['zoneId'], chat['zoneId'], chat['name'], isBot: true),
    );
  }

  Widget _buildPendingItem(Map<String, dynamic> req) {
    final sender = req['users'];
    final name = sender['display_name'] ?? sender['zone_id'];

    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFF00D2FF), child: Icon(Icons.person_add, color: Colors.black)),
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: const Text('Quiere chatear contigo', style: TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
              onPressed: () async {
                await _supabaseService.acceptMatch(req['id']);
                _loadData();
              },
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.redAccent),
              onPressed: () async {
                await _supabaseService.rejectMatch(req['id']);
                _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchItem(Map<String, dynamic> match) {
    final uid = _zoneIdService.uid;
    // Identificar cuál de los dos es el "otro"
    final bool isRequesterMe = match['requester_id'] == uid;
    final otherUser = isRequesterMe ? match['users!matches_receiver_id_fkey'] : match['users!matches_requester_id_fkey'];
    final name = otherUser['display_name'] ?? otherUser['zone_id'];

    final isMuted = _mutedMatchIds.contains(match['id']);

    return ListTile(
      leading: const CircleAvatar(backgroundColor: Color(0xFF00D2FF), child: Icon(Icons.person, color: Colors.black)),
      title: Row(
        children: [
          Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          if (isMuted) const Icon(Icons.notifications_off, color: Colors.white24, size: 16),
        ],
      ),
      subtitle: const Text('E2EE Habilitado', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              matchId: match['id'],
              otherUserName: name,
              otherZoneId: otherUser['zone_id'],
            ),
          ),
        );
      },
      onLongPress: () => _showChatOptions(match['id'], otherUser['id'] ?? otherUser['zone_id'], name, isBot: false),
    );
  }

  void _showChatOptions(String id, String otherUserId, String name, {required bool isBot}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            _buildOptionTile(
              icon: _mutedMatchIds.contains(id) ? Icons.notifications_active : Icons.notifications_off,
              title: _mutedMatchIds.contains(id) ? 'Desactivar Silencio' : 'Silenciar Chat',
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                setState(() {
                  if (_mutedMatchIds.contains(id)) {
                    _mutedMatchIds.remove(id);
                  } else {
                    _mutedMatchIds.add(id);
                  }
                });
                await prefs.setStringList('muted_chats', _mutedMatchIds.toList());
                Navigator.pop(context);
              },
            ),
            _buildOptionTile(
              icon: Icons.delete_outline,
              title: 'Eliminar Chat',
              color: Colors.orangeAccent,
              onTap: () async {
                Navigator.pop(context);
                final confirm = await _showConfirmDialog('¿Eliminar Chat?', 'Se borrará toda la conversación.');
                if (confirm == true) {
                  if (isBot) {
                    // Implementar limpieza local si es bot?
                  } else {
                    await _supabaseService.deleteMatch(id);
                  }
                  _loadData();
                }
              },
            ),
            _buildOptionTile(
              icon: Icons.block,
              title: 'Bloquear Usuario',
              color: Colors.redAccent,
              onTap: () async {
                Navigator.pop(context);
                final confirm = await _showConfirmDialog('¿Bloquear a $name?', 'No podrá escribirte ni aparecerás en su radar.');
                if (confirm == true) {
                  await _supabaseService.blockUser(_zoneIdService.uid!, otherUserId);
                  _loadData();
                }
              },
            ),
            _buildOptionTile(
              icon: Icons.report_problem_outlined,
              title: 'Reportar Usuario',
              color: Colors.redAccent,
              onTap: () async {
                Navigator.pop(context);
                final reason = await _showReportDialog(name);
                if (reason != null && reason.isNotEmpty) {
                  await _supabaseService.reportUser(_zoneIdService.uid!, otherUserId, reason);
                  await _supabaseService.blockUser(_zoneIdService.uid!, otherUserId);
                  _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Gracias por tu reporte. Hemos bloqueado al usuario.')),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({required IconData icon, required String title, required VoidCallback onTap, Color color = Colors.white70}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }

  Future<bool?> _showConfirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('CONFIRMAR', style: TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );
  }

  Future<String?> _showReportDialog(String name) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Reportar a $name', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Describe el motivo...',
            hintStyle: TextStyle(color: Colors.white24),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text), 
            child: const Text('ENVIAR REPORTE', style: TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );
  }
}
