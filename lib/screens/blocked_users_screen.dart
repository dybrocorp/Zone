import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/zone_id_service.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _supabaseService = SupabaseService();
  final _zoneIdService = ZoneIdService();
  
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final uid = _zoneIdService.uid;
      if (uid == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final users = await _supabaseService.getBlockedUsers(uid);
      if (mounted) {
        setState(() {
          _blockedUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar contactos bloqueados: $e')),
        );
      }
    }
  }

  Future<void> _unblock(String blockedId) async {
    final uid = _zoneIdService.uid;
    if (uid == null) return;

    await _supabaseService.unblockUser(uid, blockedId);
    _loadBlockedUsers();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuario desbloqueado')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Contactos Bloqueados'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2FF)))
          : _blockedUsers.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _blockedUsers.length,
                  itemBuilder: (context, index) {
                    final item = _blockedUsers[index];
                    final user = item['users'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF334155),
                          child: Text(
                            (user['display_name'] ?? '?')[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          user['display_name'] ?? 'Usuario sin nombre',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          user['zone_id'] ?? '',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: TextButton(
                          onPressed: () => _unblock(item['blocked_id']),
                          child: const Text('DESBLOQUEAR', style: TextStyle(color: Color(0xFF00D2FF))),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.block, size: 80, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          const Text(
            'No tienes contactos bloqueados',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
