import 'package:flutter/material.dart';
import 'chat_screen.dart';

class ChatsListScreen extends StatelessWidget {
  const ChatsListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Array simulado de los chats aprobados con otras personas
    final mockChats = [
      {'name': 'Alex (ZONE-1XB8C)', 'lastMsg': '¡Genial, gracias por conectarte localmente!'},
      {'name': 'María (ZONE-P9KM2)', 'lastMsg': 'Nos vemos más tarde entonces.'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Bandeja de Mensajes Seguros'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: ListView.builder(
        itemCount: mockChats.length,
        itemBuilder: (context, index) {
          final chat = mockChats[index];
          return ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF00D2FF),
              child: Icon(Icons.person, color: Colors.black),
            ),
            title: Text(chat['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(chat['lastMsg']!, style: const TextStyle(color: Colors.white54)),
            trailing: const Icon(Icons.lock, color: Colors.greenAccent, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(otherUserName: chat['name']!),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
