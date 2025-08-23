import 'package:example_flutter/domain/domain.dart';
import 'package:example_flutter/ui/app/app_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class App extends StatelessWidget {
  const App({required this.todoRepository, super.key});

  final TodoRepository todoRepository;

  @override
  Widget build(BuildContext context) {
    return Provider.value(
      value: todoRepository,
      child: MaterialApp(
        title: 'Todo + Drift + CRDT',
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: ThemeMode.system,
        home: const AppSplashScreen(),
      ),
    );
  }
}
