import 'package:example_client/example_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthKeyManager extends AuthenticationKeyManager {
  @override
  Future<String?> get() async {
    return Supabase.instance.client.auth.currentSession?.accessToken;
  }

  @override
  Future<void> put(String key) async {
    // This will never be called.
    // We use the auth methods directly from the Supabase client.
    throw UnimplementedError();
  }

  @override
  Future<void> remove() async {
    await Supabase.instance.client.auth.signOut();
  }
}
