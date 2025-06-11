import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    if (!isAuthenticated) return null;

    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', currentUser!.id)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      return null;
    }
  }

  Future<void> ensureProfileExists() async {
    if (!isAuthenticated) return;

    try {
      final profile = await getCurrentUserProfile();
      if (profile != null) return;

      // Create new profile if it doesn't exist
      await _client.from('profiles').insert({
        'id': currentUser!.id,
        'email': currentUser!.email,
        'name': currentUser!.userMetadata?['full_name'] ??
            currentUser!.email?.split('@')[0],
        'role': 'user',
      });
    } catch (e) {
      debugPrint('Error ensuring profile exists: $e');
    }
  }
}
