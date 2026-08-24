// features/auth/data/auth_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase's auth client. Keeps every direct
/// `supabase_flutter` call in one place so the presentation layer never
/// touches the SDK directly.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  /// Emits on every sign-in, sign-out, and token-refresh event.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// If the Supabase project has "Confirm email" enabled (the default),
  /// `response.session` will be null until the user clicks the confirmation
  /// link — the caller should check that and show the right message.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();
}
