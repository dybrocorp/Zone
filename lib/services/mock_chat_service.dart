import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MockChatService {
  static final MockChatService _instance = MockChatService._internal();
  factory MockChatService() => _instance;
  MockChatService._internal();

  static const String _keyActiveMockChats = 'active_mock_chats';
  static const String _prefixMessages = 'mock_messages_';

  /// Obtiene la lista de bots con los que el usuario ha interactuado.
  Future<List<Map<String, dynamic>>> getActiveMockChats() async {
    final prefs = await SharedPreferences.getInstance();
    final String? chatsJson = prefs.getString(_keyActiveMockChats);
    if (chatsJson == null) return [];
    try {
      final List<dynamic> list = jsonDecode(chatsJson);
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Añade un bot a la lista de chats activos si no está ya.
  Future<void> activateMockChat(String zoneId, String name, String? avatarUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final chats = await getActiveMockChats();
    
    if (chats.any((c) => c['zoneId'] == zoneId)) return;

    chats.add({
      'zoneId': zoneId,
      'name': name,
      'avatarUrl': avatarUrl,
      'lastMessage': '¡Conectados!',
      'timestamp': DateTime.now().toIso8601String(),
    });

    await prefs.setString(_keyActiveMockChats, jsonEncode(chats));
  }

  /// Guarda un mensaje para un bot específico.
  Future<void> saveMessage(String zoneId, String text, bool isMe) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_prefixMessages$zoneId';
    
    final List<Map<String, dynamic>> messages = await getMessages(zoneId);
    messages.add({
      'text': text,
      'isMe': isMe,
      'timestamp': DateTime.now().toIso8601String(),
    });

    await prefs.setString(key, jsonEncode(messages));

    // Actualizar el último mensaje en la lista de chats
    final chats = await getActiveMockChats();
    final index = chats.indexWhere((c) => c['zoneId'] == zoneId);
    if (index != -1) {
      chats[index]['lastMessage'] = text;
      chats[index]['timestamp'] = DateTime.now().toIso8601String();
      await prefs.setString(_keyActiveMockChats, jsonEncode(chats));
    }
  }

  /// Recupera la historia de mensajes con un bot.
  Future<List<Map<String, dynamic>>> getMessages(String zoneId) async {
    final prefs = await SharedPreferences.getInstance();
    final String key = '$_prefixMessages$zoneId';
    final String? msgsJson = prefs.getString(key);
    if (msgsJson == null) return [];
    try {
      final List<dynamic> list = jsonDecode(msgsJson);
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Limpia los chats mock (por ejemplo al cerrar sesión).
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final chats = await getActiveMockChats();
    for (var chat in chats) {
      await prefs.remove('$_prefixMessages${chat['zoneId']}');
    }
    await prefs.remove(_keyActiveMockChats);
  }
}
