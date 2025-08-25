import 'package:example_flutter/domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class UserLabelComponent extends StatelessWidget {
  const UserLabelComponent({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepository = context.read<AuthRepository>();

    try {
      final userEmail = authRepository.getUserEmail();
      return Text(userEmail ?? 'Unknown user');
    } on Object catch (e) {
      debugPrint('Error while getting user email: $e');
      return const Text('Unknown user');
    }
  }
}
