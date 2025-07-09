// lib/services/notification_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();
  static final _supabase = Supabase.instance.client;

  // Notification channels
  static const AndroidNotificationChannel _highImportanceChannel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _taskChannel = AndroidNotificationChannel(
    'task_notifications',
    'Task Notifications',
    description: 'Notifications for task assignments and updates',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Initialize the notification service
  static Future<void> initialize() async {
    // Request permissions
    await _requestPermissions();
    
    // Initialize local notifications
    await _initializeLocalNotifications();
    
    // Create notification channels
    await _createNotificationChannels();
    
    // Set up message handlers
    _setupMessageHandlers();
  }

  /// Request notification permissions
  static Future<void> _requestPermissions() async {
    final NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (kDebugMode) {
      print('Notification permission status: ${settings.authorizationStatus}');
    }
  }

  /// Initialize local notifications
  static Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// Create notification channels
  static Future<void> _createNotificationChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(_highImportanceChannel);
      await androidPlugin.createNotificationChannel(_taskChannel);
    }
  }

  /// Setup message handlers
  static void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  }

  /// Handle foreground messages
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      print('Received foreground message: ${message.messageId}');
      
      // Handle notification content (from Firebase Console or proper notification structure)
      if (message.notification != null) {
        print('Notification Title: ${message.notification!.title}');
        print('Notification Body: ${message.notification!.body}');
        if (message.notification!.android != null) {
          print('Android notification data: ${message.notification!.android}');
        }
        if (message.notification!.apple != null) {
          print('Apple notification data: ${message.notification!.apple}');
        }
      }
      
      // Handle data payload (from programmatic sends or additional data)
      if (message.data.isNotEmpty) {
        print('Data payload: ${message.data}');
      } else {
        print('No data payload (likely sent from Firebase Console without additional data)');
      }
      
      // Additional message properties
      print('Message from: ${message.from}');
      print('Message sent time: ${message.sentTime}');
      print('Message category: ${message.category}');
    }

    await showLocalNotification(message);
  }

  /// Handle notification tap
  static Future<void> _handleNotificationTap(RemoteMessage message) async {
    if (kDebugMode) {
      print('Notification tapped: ${message.messageId}');
    }
    
    // Handle navigation based on notification data
    // For Firebase Console notifications, check if there's any data payload
    Map<String, dynamic> navigationData = message.data;
    
    // If no data payload, try to extract from notification content
    if (navigationData.isEmpty && message.notification != null) {
      // Create a basic navigation data structure from notification
      navigationData = {
        'type': 'general',
        'title': message.notification!.title,
        'body': message.notification!.body,
      };
    }
    
    await _handleNotificationNavigation(navigationData);
  }

  /// Handle notification response when tapped
  static Future<void> _onNotificationTapped(NotificationResponse response) async {
    if (response.payload != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(response.payload!);
        await _handleNotificationNavigation(data);
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing notification payload: $e');
        }
        // Handle as general notification if payload parsing fails
        await _handleNotificationNavigation({'type': 'general'});
      }
    }
  }

  /// Handle navigation based on notification data
  static Future<void> _handleNotificationNavigation(Map<String, dynamic> data) async {
    // Implement navigation logic based on notification type
    final String? notificationType = data['type'];
    final String? taskId = data['task_id'];
    
    switch (notificationType) {
      case 'task_assigned':
        // Navigate to task details
        print('Navigate to task: $taskId');
        break;
      case 'task_completed':
        // Navigate to completed tasks
        print('Navigate to completed tasks');
        break;
      case 'task_due_soon':
        // Navigate to task details
        print('Navigate to due task: $taskId');
        break;
      case 'general':
        // Handle general notifications (like from Firebase Console)
        print('General notification tapped');
        break;
      default:
        print('Unknown notification type: $notificationType');
    }
  }

  /// Show local notification
  static Future<void> showLocalNotification(RemoteMessage message) async {
    // Get notification type from data payload, fallback to general
    final String? notificationType = message.data['type'];
    final String channelId = _getChannelId(notificationType);
    
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'task_notifications' ? 'Task Notifications' : 'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF2196F3),
      playSound: true,
      enableVibration: true,
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidDetails,
    );

    // Create payload with both notification and data content
    final Map<String, dynamic> payload = {
      ...message.data,
      'type': notificationType ?? 'general',
    };
    
    // Add notification content to payload if available
    if (message.notification != null) {
      payload['notification_title'] = message.notification!.title;
      payload['notification_body'] = message.notification!.body;
    }

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'Taskaty',
      message.notification?.body ?? 'New notification',
      platformChannelSpecifics,
      payload: jsonEncode(payload),
    );
  }

  /// Get appropriate channel ID based on notification type
  static String _getChannelId(String? notificationType) {
    switch (notificationType) {
      case 'task_assigned':
      case 'task_completed':
      case 'task_due_soon':
        return 'task_notifications';
      default:
        return 'high_importance_channel';
    }
  }

  /// Get and save FCM token
  static Future<String?> getAndSaveFCMToken([String? userId]) async {
    try {
      final String? token = await _firebaseMessaging.getToken();
      
      if (token != null) {
        if (kDebugMode) {
          print('FCM Token: $token');
        }
        
        // Save token if user is provided or current user exists
        final String? currentUserId = userId ?? _supabase.auth.currentUser?.id;
        if (currentUserId != null) {
          await _saveFCMToken(token, currentUserId);
        }
      }
      
      return token;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting FCM token: $e');
      }
      return null;
    }
  }

  /// Save FCM token to Supabase
  static Future<void> _saveFCMToken(String token, String userId) async {
    try {
      await _supabase.from('user_tokens').upsert({
        'user_id': userId,
        'fcm_token': token,
        'updated_at': DateTime.now().toIso8601String(),
        'device_type': defaultTargetPlatform.name,
      });
      
      if (kDebugMode) {
        print('FCM token saved successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving FCM token: $e');
      }
    }
  }

  /// Setup token refresh listener
  static void setupTokenRefreshListener() {
    _firebaseMessaging.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) {
        print('FCM Token refreshed: $newToken');
      }
      
      final String? currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        await _saveFCMToken(newToken, currentUserId);
      }
    });
  }

  /// Delete FCM token on logout
  static Future<void> deleteFCMToken() async {
    try {
      final String? currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        await _supabase
            .from('user_tokens')
            .delete()
            .eq('user_id', currentUserId);
        
        if (kDebugMode) {
          print('FCM token deleted successfully');
        }
      }
      
      await _firebaseMessaging.deleteToken();
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting FCM token: $e');
      }
    }
  }

  /// Send task assignment notification
  static Future<bool> sendTaskAssignmentNotification({
    required int taskId,
    required String assignedUserId,
    required String assignedById,
    required String taskTitle,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'notify-task-assignment',
        body: {
          'task_id': taskId,
          'user_id': assignedUserId,
          'assigned_by_id': assignedById,
          'task_title': taskTitle,
          'type': 'task_assigned',
        },
      );

      if (response.status == 200) {
        if (kDebugMode) {
          print('Task assignment notification sent successfully');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('Failed to send task assignment notification: ${response.data}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending task assignment notification: $e');
      }
      return false;
    }
  }

  /// Send task update notification
  static Future<bool> sendTaskUpdateNotification({
    required String taskId,
    required String taskTitle,
    required String assignedUserId,
    required String updateType, // 'completed', 'updated', 'due_soon'
    String? message,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'notify-task-update',
        body: {
          'task_id': taskId,
          'task_title': taskTitle,
          'assigned_user_id': assignedUserId,
          'update_type': updateType,
          'type': updateType,
          'message': message,
        },
      );

      if (response.status == 200) {
        if (kDebugMode) {
          print('Task update notification sent successfully');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('Failed to send task update notification: ${response.data}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending task update notification: $e');
      }
      return false;
    }
  }

  /// Send bulk notifications to multiple users
  static Future<bool> sendBulkNotifications({
    required List<String> userIds,
    required String title,
    required String body,
    String? notificationType,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'send-bulk-notifications',
        body: {
          'user_ids': userIds,
          'title': title,
          'body': body,
          'type': notificationType ?? 'general',
          'data': data ?? {},
        },
      );

      if (response.status == 200) {
        if (kDebugMode) {
          print('Bulk notifications sent successfully');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('Failed to send bulk notifications: ${response.data}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending bulk notifications: $e');
      }
      return false;
    }
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    final NotificationSettings settings = await _firebaseMessaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  /// Get initial message (when app is opened from terminated state)
  static Future<RemoteMessage?> getInitialMessage() async {
    return await _firebaseMessaging.getInitialMessage();
  }
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('Handling background message: ${message.messageId}');
    
    // Log both notification and data content
    if (message.notification != null) {
      print('Background notification - Title: ${message.notification!.title}');
      print('Background notification - Body: ${message.notification!.body}');
    }
    
    if (message.data.isNotEmpty) {
      print('Background data payload: ${message.data}');
    }
  }
  
  // You can handle background messages here
  // For example, update local database, show notification, etc.
  // Note: You can't update UI from background handler
}