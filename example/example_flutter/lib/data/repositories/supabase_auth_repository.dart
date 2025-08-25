import 'package:example_flutter/domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({
    required SupabaseClient client,
  }) : _client = client;

  final SupabaseClient _client;

  @override
  Stream<bool> get isAuthenticated {
    return _client.auth.onAuthStateChange.map((event) => event.session != null);
  }

  @override
  Future<AuthResponse> logIn(
    String email,
    String password,
  ) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  @override
  Future<AuthResponse> signUp(
    String email,
    String password,
  ) async {
    return await _client.auth.signUp(email: email, password: password);
  }

  @override
  Future<void> logOut() async {
    await _client.auth.signOut();
  }

  @override
  String? getUserEmail() {
    final session = _client.auth.currentSession;
    final user = session?.user;
    return user?.email;
  }
}
