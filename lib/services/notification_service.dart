import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// ID del match que el usuario tiene abierto actualmente.
  /// Si un mensaje llega para este ID, no mostraremos notificación.
  static String? currentActiveMatchId;

  Future<void> init() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Manejar toque en la notificación
      },
    );

    _isInitialized = true;
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (status.isGranted) {
        // Permiso concedido
      }
    }
  }

  Future<void> showNotification({
    int id = 0,
    required String title,
    required String body,
    String? payload,
    String channelId = 'zone_general',
    String channelName = 'Notificaciones Generales',
  }) async {
    await init();

    AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }

  Future<void> showDiscoveryNotification(String name) async {
    await showNotification(
      id: 1,
      title: '¡Nueva persona cerca!',
      body: '$name está en tu radar. ¡Saluda!',
      channelId: 'zone_discovery',
      channelName: 'Descubrimiento de Personas',
    );
  }

  Future<void> showMessageNotification(String senderName, String message) async {
    await showNotification(
      id: 2,
      title: 'Nuevo mensaje de $senderName',
      body: message,
      channelId: 'zone_messages',
      channelName: 'Mensajes de Chat',
    );
  }

  Future<void> showMatchRequestNotification(String name) async {
    await showNotification(
      id: 3,
      title: 'Nueva solicitud de Zone',
      body: '$name quiere conectar contigo.',
      channelId: 'zone_requests',
      channelName: 'Solicitudes de Match',
    );
  }
}
