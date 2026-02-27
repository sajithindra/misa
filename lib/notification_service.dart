import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SecurityAlert {
  final String type;
  final String message;
  final String name;
  final String source;
  final DateTime timestamp;

  SecurityAlert({
    required this.type,
    required this.message,
    required this.name,
    required this.source,
    required this.timestamp,
  });

  factory SecurityAlert.fromJson(Map<String, dynamic> json) {
    return SecurityAlert(
      type: json['type'] ?? 'UNKNOWN',
      message: json['message'] ?? '',
      name: json['name'] ?? 'Unknown',
      source: json['source'] ?? 'Unknown',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        ((json['timestamp'] ?? 0) * 1000).toInt(),
      ),
    );
  }
}

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  final List<SecurityAlert> _alerts = [];
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  List<SecurityAlert> get alerts => List.unmodifiable(_alerts);
  bool get isConnected => _isConnected;

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );
    await _localNotifications.initialize(initializationSettings);
  }

  void connect(String ip) {
    if (_isConnected) return;

    final uri = Uri.parse('ws://$ip:8000/ws/alerts');
    debugPrint('Connecting to alerts: $uri');

    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      notifyListeners();

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
          debugPrint('Alert WebSocket disconnected');
        },
        onError: (error) {
          _isConnected = false;
          notifyListeners();
          debugPrint('Alert WebSocket error: $error');
        },
      );
    } catch (e) {
      _isConnected = false;
      notifyListeners();
      debugPrint('Failed to connect to alerts: $e');
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message);
      final alert = SecurityAlert.fromJson(data);

      _alerts.insert(0, alert);
      if (_alerts.length > 100) _alerts.removeLast();

      _showLocalNotification(alert);
      notifyListeners();
    } catch (e) {
      debugPrint('Error parsing alert message: $e');
    }
  }

  Future<void> _showLocalNotification(SecurityAlert alert) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'security_alerts',
          'Security Alerts',
          channelDescription: 'Notifications for high security threats',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          color: Color(0xFFFF0000),
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      alert.timestamp.millisecondsSinceEpoch % 10000,
      'SECURITY ALERT',
      alert.message,
      platformChannelSpecifics,
    );
  }

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    notifyListeners();
  }
}
