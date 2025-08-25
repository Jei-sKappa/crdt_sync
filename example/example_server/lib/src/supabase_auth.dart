import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:serverpod/serverpod.dart';

class SupabaseAuthValidator {
  final String supabaseUrl;
  final String supabaseAnonKey;

  const SupabaseAuthValidator({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  Future<AuthenticationInfo?> validate(Session session, String token) async {
    if (token.isEmpty) return null;

    final uri = Uri.parse('$supabaseUrl/auth/v1/user');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'apikey': supabaseAnonKey,
      },
    );

    if (response.statusCode != 200) return null;

    final Map<String, dynamic> json = jsonDecode(response.body);
    final String? userId = json['id'] as String?;
    if (userId == null || userId.isEmpty) return null;

    return AuthenticationInfo(userId, <Scope>{});
  }
}
