import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/mock_chat_service.dart';
import '../services/supabase_service.dart';
import '../services/zone_id_service.dart';
import '../services/notification_service.dart';

class MockChatScreen extends StatefulWidget {
  final String botName;
  final String zoneId;
  final String? avatarUrl;

  const MockChatScreen({
    super.key,
    required this.botName,
    required this.zoneId,
    this.avatarUrl,
  });

  @override
  _MockChatScreenState createState() => _MockChatScreenState();
}

class _MockChatScreenState extends State<MockChatScreen> {
  final _mockChatService = MockChatService();
  final _supabaseService = SupabaseService();
  final _zoneIdService = ZoneIdService();
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  bool _isBlocked = false;

  final List<String> _randomReplies = [
    "¡Hola! Soy un bot simulando el funcionamiento de la app. ¿Qué tal?",
    "Me encanta el diseño oscuro de esta app.",
    "Jaja, interesante. Cuéntame más.",
    "El radar es una característica excelente para conocer a la gente alrededor.",
    "Estoy testeando cómo se deslizan los mensajes. 🚀",
    "¿Ya probaste cambiar tu foto de perfil con la nueva política en el Bucket?",
    "¡Todo parece marchar de maravilla! ✌️",
  ];

  @override
  void initState() {
    super.initState();
    NotificationService.currentActiveMatchId = widget.zoneId;
    _loadMessages();
  }

  @override
  void dispose() {
    if (NotificationService.currentActiveMatchId == widget.zoneId) {
      NotificationService.currentActiveMatchId = null;
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final history = await _mockChatService.getMessages(widget.zoneId);
    
    // Verificar si está bloqueado
    final uid = _zoneIdService.uid;
    if (uid != null) {
      final blocked = await _supabaseService.getBlockedUsers(uid);
      _isBlocked = blocked.any((b) => b['blocked_id'] == widget.zoneId);
    }

    if (mounted) {
      setState(() {
        if (history.isEmpty) {
          _messages.add({
            'text': '¡Hola! He aceptado tu solicitud de inmediato. Pruébame enviándome un mensaje.',
            'isMe': false,
          });
        } else {
          _messages = history;
        }
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    // Guardar localmente (Persistencia)
    await _mockChatService.saveMessage(widget.zoneId, text, true);

    setState(() {
      _messages.add({
        'text': text,
        'isMe': true,
      });
      _isTyping = true;
    });
    _scrollToBottom();

    // Simular el retraso en leer y "escribir" la respuesta
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    final randomReply = _randomReplies[Random().nextInt(_randomReplies.length)];
    
    // Guardar respuesta del bot (Persistencia)
    await _mockChatService.saveMessage(widget.zoneId, randomReply, false);

    // Notificar si no estamos en este chat
    if (NotificationService.currentActiveMatchId != widget.zoneId) {
      NotificationService().showMessageNotification(widget.botName, randomReply);
    }

    setState(() {
      _isTyping = false;
      _messages.add({
        'text': randomReply,
        'isMe': false,
      });
    });
    _scrollToBottom();
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
            Text(widget.botName, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 1,
      ),
      body: Column(
        children: [
          if (_isBlocked)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              width: double.infinity,
              color: Colors.redAccent.withOpacity(0.1),
              child: const Text(
                '🚫 HAS BLOQUEADO A ESTE USUARIO',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              width: double.infinity,
              color: Colors.greenAccent.withOpacity(0.1),
              child: const Text(
                '🔒 (SIMULACIÓN BOT DE PRUEBA)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['isMe'];
                
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
                      msg['text'],
                      style: TextStyle(
                        color: isMe ? Colors.black : Colors.white, 
                        fontSize: 16, 
                        fontWeight: FontWeight.w500
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${widget.botName} está escribiendo...', style: const TextStyle(color: Colors.white54, fontStyle: FontStyle.italic, fontSize: 12)),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1E293B),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: !_isBlocked,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _isBlocked ? 'Usuario bloqueado' : 'Escribe un mensaje...',
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
                    backgroundColor: _isBlocked ? Colors.grey : const Color(0xFF00D2FF),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.black, size: 20),
                      onPressed: _isBlocked ? null : _sendMessage,
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
