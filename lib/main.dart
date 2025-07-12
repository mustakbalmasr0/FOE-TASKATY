// lib/main.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:taskaty/router/auth_router.dart';
import 'package:taskaty/pages/dashboard.dart';
import 'package:taskaty/pages/admin_page.dart';
import 'package:taskaty/pages/user_page.dart';
import 'package:taskaty/auth/login.dart';

// Conditional imports for Firebase (only on mobile)
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:taskaty/services/notification_service.dart';

// Global flag to track Supabase initialization
bool _supabaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: "./.env");

  // Initialize Firebase only on mobile platforms
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Initialize notification service
      await NotificationService.initialize();

      // Setup token refresh listener
      NotificationService.setupTokenRefreshListener();
    } catch (e) {
      print('Firebase initialization failed: $e');
    }
  }

  // Initialize Supabase
  await _initializeSupabase();

  // Listen for Supabase auth state changes and save FCM token for logged-in users
  Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
    final session = data.session;
    print('Auth state changed: ${data.event}');

    if (session != null && session.user != null) {
      print('User signed in: ${session.user.id}');

      // Wait a moment to ensure FCM token is available
      await Future.delayed(Duration(milliseconds: 500));

      // Check and ensure FCM token exists for the user
      if (!kIsWeb) {
        try {
          await NotificationService.checkAndEnsureFCMToken(session.user.id);
          print('FCM token checked and ensured for user: ${session.user.id}');
        } catch (e) {
          print('Failed to check/ensure FCM token: $e');
        }
      }
    } else {
      print('User signed out');
    }
  });

  runApp(MyApp());
}

// Background message handler (only used on mobile)
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!kIsWeb) {
    // Only initialize Firebase if it hasn't been initialized yet
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Firebase might already be initialized, which is fine
      print('Firebase already initialized in background handler');
    }
    print('Handling a background message: ${message.messageId}');
  }
}

Future<void> _initializeSupabase() async {
  // Guard against multiple initializations
  if (_supabaseInitialized) {
    print('Supabase already initialized, skipping...');
    return;
  }

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseApiKey = dotenv.env['SUPABASE_API_KEY'];

  if (supabaseUrl == null || supabaseApiKey == null) {
    throw Exception(
        'SUPABASE_URL or SUPABASE_API_KEY is missing in assets/.env');
  }

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseApiKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _supabaseInitialized = true;
    print('Supabase initialized successfully');
  } catch (e) {
    if (e.toString().contains('already initialized')) {
      print('Supabase was already initialized elsewhere');
      _supabaseInitialized = true;
    } else {
      print('Supabase initialization failed: $e');
      rethrow;
    }
  }
}

class FCMTokenNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Save FCM token when navigating to dashboard or user page
    final routeName = route.settings.name ?? '';
    if (routeName == '/admin/dashboard' ||
        routeName == '/admin/create-task' ||
        routeName == '/user/dashboard') {
      NotificationService.getAndSaveFCMToken();
    }
    super.didPush(route, previousRoute);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taskaty',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        dropdownMenuTheme: const DropdownMenuThemeData(
          menuStyle: MenuStyle(
            minimumSize: MaterialStatePropertyAll(Size(200, 40)),
          ),
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      // Show LoginScreen as the home page
      home: const LoginScreen(),
      navigatorObservers: [FCMTokenNavigatorObserver()],
      routes: {
        '/login': (context) => const LoginScreen(),
        '/auth': (context) => const AuthRouter(),
        '/admin/dashboard': (context) => const DashboardPage(),
        '/admin/create-task': (context) => const AdminDashboard(),
        '/user/dashboard': (context) => const UserDashboard(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}