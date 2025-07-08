import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:taskaty/router/auth_router.dart';
import 'package:taskaty/pages/dashboard.dart';
import 'package:taskaty/pages/admin_page.dart';
import 'package:taskaty/pages/user_page.dart';
import 'package:taskaty/auth/login.dart';

void main() async {
  // Ensure plugin binding is initialized before any plugin usage.
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  await dotenv.load(fileName: "assets/.env");

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseApiKey = dotenv.env['SUPABASE_API_KEY'];

  if (supabaseUrl == null || supabaseApiKey == null) {
    throw Exception(
        'SUPABASE_URL or SUPABASE_API_KEY is missing in assets/.env');
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseApiKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // Initialize FCM
  await _initializeFCM();

  runApp(MyApp());
}

Future<void> _initializeFCM() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  
  // Request permission for notifications
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('User granted permission');
  } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
    print('User granted provisional permission');
  } else {
    print('User declined or has not accepted permission');
  }

  // Get FCM token
  String? token = await messaging.getToken();
  print('FCM Token: $token');
  
  // Save token to Supabase if user is authenticated
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser != null && token != null) {
    await _saveFCMToken(token, currentUser.id);
  }

  // Handle token refresh
  messaging.onTokenRefresh.listen((newToken) async {
    print('FCM Token refreshed: $newToken');
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      await _saveFCMToken(newToken, currentUser.id);
    }
  });

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Got a message whilst in the foreground!');
    print('Message data: ${message.data}');

    if (message.notification != null) {
      print('Message also contained a notification: ${message.notification}');
    }
  });

  // Handle background messages
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
}

Future<void> _saveFCMToken(String token, String userId) async {
  try {
    await Supabase.instance.client.from('user_tokens').upsert({
      'user_id': userId,
      'fcm_token': token,
      'updated_at': DateTime.now().toIso8601String(),
    });
    print('FCM token saved to Supabase');
  } catch (e) {
    print('Error saving FCM token: $e');
  }
}

// Top-level function to handle background messages
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
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
      home: const LoginScreen(),
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
        _navigateToAuth();
      }
    });
  }

  void _handleSignedIn(User? user) async {
    if (!mounted) return;
    
    // Save FCM token when user signs in
    if (user != null) {
      await _saveUserFCMToken(user.id);
    }
    
    if (user?.userMetadata?['role'] == 'admin') {
      Navigator.of(context).pushReplacementNamed('/admin/dashboard');
    } else {
      Navigator.of(context).pushReplacementNamed('/user/dashboard');
    }
  }

  Future<void> _saveUserFCMToken(String userId) async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      String? token = await messaging.getToken();
      
      if (token != null) {
        await Supabase.instance.client.from('user_tokens').upsert({
          'user_id': userId,
          'fcm_token': token,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      print('Error saving FCM token on sign in: $e');
    }
  }

  void _navigateToAuth() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/auth');
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