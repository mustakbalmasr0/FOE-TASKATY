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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: "assets/.env");

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
      
      // Get and save initial FCM token
      await NotificationService.getAndSaveFCMToken();
      
      // Handle initial message when app is opened from terminated state
      final RemoteMessage? initialMessage = await NotificationService.getInitialMessage();
      if (initialMessage != null) {
        print('App opened from notification: ${initialMessage.messageId}');
      }
    } catch (e) {
      print('Firebase initialization failed: $e');
    }
  }

  // Initialize Supabase
  await _initializeSupabase();

  runApp(MyApp());
}

// Background message handler (only used on mobile)
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!kIsWeb) {
    await Firebase.initializeApp();
    print('Handling a background message: ${message.messageId}');
  }
}

Future<void> _initializeSupabase() async {
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseApiKey = dotenv.env['SUPABASE_API_KEY'];

  if (supabaseUrl == null || supabaseApiKey == null) {
    throw Exception('SUPABASE_URL or SUPABASE_API_KEY is missing in assets/.env');
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseApiKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
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
      home: const AuthStateScreen(),
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

class AuthStateScreen extends StatefulWidget {
  const AuthStateScreen({super.key});

  @override
  State<AuthStateScreen> createState() => _AuthStateScreenState();
}

class _AuthStateScreenState extends State<AuthStateScreen> {
  late final StreamSubscription<AuthState> _authStateSubscription;
  User? _user;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;

      if (mounted) {
        setState(() {
          _user = session?.user;
          _isInitialized = true;
        });
      }

      _authStateSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final AuthChangeEvent event = data.event;
        final Session? session = data.session;

        if (mounted) {
          setState(() {
            _user = session?.user;
          });
        }

        if (event == AuthChangeEvent.signedIn) {
          _handleSignedIn(session?.user);
        } else if (event == AuthChangeEvent.signedOut) {
          _handleSignedOut();
        }
      });
    } catch (e) {
      print('Auth initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  Future<void> _handleSignedIn(User? user) async {
    if (!mounted || user == null) return;

    // Get and save FCM token when user signs in (only on mobile)
    if (!kIsWeb) {
      try {
        await NotificationService.getAndSaveFCMToken(user.id);
      } catch (e) {
        print('FCM token save failed: $e');
      }
    }

    // Navigate based on user role
    if (user.userMetadata?['role'] == 'admin') {
      Navigator.of(context).pushReplacementNamed('/admin/dashboard');
    } else {
      Navigator.of(context).pushReplacementNamed('/user/dashboard');
    }
  }

  Future<void> _handleSignedOut() async {
    // Delete FCM token on logout (only on mobile)
    if (!kIsWeb) {
      try {
        await NotificationService.deleteFCMToken();
      } catch (e) {
        print('FCM token deletion failed: $e');
      }
    }

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/auth');
    }
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_user == null) {
      return const AuthRouter();
    }

    if (_user?.userMetadata?['role'] == 'admin') {
      return const DashboardPage();
    }

    return const UserDashboard();
  }
}