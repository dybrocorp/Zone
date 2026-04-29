import 'package:flutter/material.dart';
import 'chat_screen.dart';
import '../services/supabase_service.dart';
import '../services/zone_id_service.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({Key? key}) : super(key: key);

  @override
  _ChatsListScreenState createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final _supabaseService = SupabaseService();
  final _zoneIdService = ZoneIdService();
  
  List<Map<String, dynamic>> _matches = [];
  List<Map<String, dynamic>> _pendingRequests = [];
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

      if (mounted) {
        setState(() {
          _matches = matches;
          _pendingRequests = pending;
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
                ],
              ),
            ),
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

    return ListTile(
      leading: const CircleAvatar(backgroundColor: Color(0xFF00D2FF), child: Icon(Icons.person, color: Colors.black)),
      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    );
  }
}
