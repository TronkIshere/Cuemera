// features/auth/presentation/providers/auth_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

/// Fires on every sign-in / sign-out / token-refresh event. Useful at the
/// app root later if you want to gate Splash/Home behind a session check.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// The currently signed-in user, or null. Reactive: updates whenever
/// [authStateChangesProvider] emits, falling back to the repository's
/// synchronous value before the stream has emitted anything yet.
final currentUserProvider = Provider<User?>((ref) {
  final streamed = ref.watch(authStateChangesProvider).valueOrNull;
  if (streamed != null) return streamed.session?.user;
  return ref.watch(authRepositoryProvider).currentUser;
});

enum AuthSignUpResult { signedIn, confirmationRequired }

/// Drives the loading/error state for the Login and Register screens.
/// `state` is only "idle / loading / error" for the *action itself* —
/// the actual session lives in [authStateChangesProvider].
class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._repository) : super(const AsyncValue.data(null));

  final AuthRepository _repository;

  Future<bool> signIn({required String email, required String password}) async {
    state = const AsyncValue.loading();
    try {
      await _repository.signIn(email: email, password: password);
      state = const AsyncValue.data(null);
      return true;
    } catch (error, stackTrace) {
      state = AsyncValue.error(_friendlyMessage(error), stackTrace);
      return false;
    }
  }

  Future<AuthSignUpResult?> signUp({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    try {
      final response = await _repository.signUp(
        email: email,
        password: password,
      );
      state = const AsyncValue.data(null);
      return response.session == null
          ? AuthSignUpResult.confirmationRequired
          : AuthSignUpResult.signedIn;
    } catch (error, stackTrace) {
      state = AsyncValue.error(_friendlyMessage(error), stackTrace);
      return null;
    }
  }

  String _friendlyMessage(Object error) {
    if (error is AuthException) return error.message;
    return 'Something went wrong. Please try again.';
  }
}

final authControllerProvider =
    StateNotifierProvider.autoDispose<AuthController, AsyncValue<void>>((
      ref,
    ) {
      return AuthController(ref.watch(authRepositoryProvider));
    });
