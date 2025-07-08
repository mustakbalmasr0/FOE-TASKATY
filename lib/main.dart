import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:taskaty/router/auth_router.dart';
import 'package:taskaty/pages/dashboard.dart';
import 'package:taskaty/pages/admin_page.dart';
import 'package:taskaty/pages/user_page.dart';
import 'package:taskaty/auth/login.dart';

void main() async {
  // Ensure plugin binding is initialized before any plugin usage.
  WidgetsFlutterBinding.ensureInitialized();

  

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
  runApp(MyApp());
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

  void _handleSignedIn(User? user) {
    if (!mounted) return;
    if (user?.userMetadata?['role'] == 'admin') {
      Navigator.of(context).pushReplacementNamed('/admin/dashboard');
    } else {
      Navigator.of(context).pushReplacementNamed('/user/dashboard');
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
