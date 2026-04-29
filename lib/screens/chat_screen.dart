import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/zone_id_service.dart';
import '../services/chat_e2ee_service.dart';

class ChatScreen extends StatefulWidget {
  final String matchId;
  final String otherUserName;
  final String otherZoneId;

  const ChatScreen({
    super.key,
    required this.matchId,
    required this.otherUserName,
    required this.otherZoneId,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _supabaseService = SupabaseService();
  final _zoneIdService = ZoneIdService();
  final _e2eeService = ChatE2EEService();
  
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  SecretKey? _sharedSecret;
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _setupChat();
  }

  Future<void> _setupChat() async {
    final uid = _zoneIdService.uid;
    if (uid == null) return;

    // 1. Obtener la clave pública del otro usuario de Supabase
    final otherProfile = await _supabaseService.getProfileByZoneId(widget.otherZoneId);
    if (otherProfile != null) {
      final otherPubKeyBase64 = otherProfile['public_key'];
      final otherPubKey = _e2eeService.importPublicKeyFromBase64(otherPubKeyBase64);
      
      // 2. Calcular el secreto compartido (Shared Secret) para esta sesión
      _sharedSecret = await _e2eeService.computeSharedSecret(otherPubKey);
    }

    // 3. Cargar historial de mensajes existentes
    final history = await _supabaseService.getMessages(widget.matchId);
    
    // 4. Suscribirse a mensajes nuevos en tiempo real
    _subscription = _supabaseService.subscribeToMessages(widget.matchId, (newMsg) {
      if (mounted) {
        setState(() {
          _messages.add(newMsg);
        });
      }
    });

    if (mounted) {
      setState(() {
        _messages.addAll(history);
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sharedSecret == null) return;

    final uid = _zoneIdService.uid;
    if (uid == null) return;

    final controllerText = text;
    _messageController.clear();

    // Encriptar mensaje con E2EE real
    final encrypted = await _e2eeService.encryptMessage(controllerText, _sharedSecret!);

    await _supabaseService.sendMessage(
      matchId: widget.matchId,
      senderId: uid,
      encryptedContent: encrypted['encrypted_content'],
      nonce: encrypted['nonce'],
      mac: encrypted['mac'],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.lock, size: 16, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Text(widget.otherUserName, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 1,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            width: double.infinity,
            color: Colors.greenAccent.withOpacity(0.1),
            child: const Text(
              '🔒 Los mensajes están cifrados de extremo a extremo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.greenAccent, fontSize: 12),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2FF)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isMe = msg['sender_id'] == _zoneIdService.uid;
                    
                    return FutureBuilder<String>(
                      future: _sharedSecret != null 
                        ? _e2eeService.decryptMessage(
                            msg['encrypted_content'], 
                            msg['nonce'], 
                            msg['mac'], 
                            _sharedSecret!
                          )
                        : Future.value('Cifrado...'),
                      builder: (context, snapshot) {
                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFF00D2FF) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(16).copyWith(
                                bottomRight: isMe ? Radius.zero : null,
                                bottomLeft: !isMe ? Radius.circular(16) : null,
                              ),
                              border: isMe ? null : Border.all(color: Colors.white10),
                            ),
                            child: Text(
                              snapshot.data ?? '...',
                              style: TextStyle(
                                color: isMe ? Colors.black : Colors.white, 
                                fontSize: 16, 
                                fontWeight: FontWeight.w500
                              ),
                            ),
                          ),
                        );
                      }
                    );
                  },
                ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Mensaje seguro...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF00D2FF),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black, size: 20),
                    onPressed: _sendMessage,
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
