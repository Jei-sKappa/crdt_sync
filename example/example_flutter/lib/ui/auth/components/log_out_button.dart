import 'package:example_flutter/domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LogOutButton extends StatelessWidget {
  const LogOutButton({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepository = context.read<AuthRepository>();

    return IconButton(
      onPressed: authRepository.logOut,
      icon: const Icon(Icons.logout),
    );
  }
}
