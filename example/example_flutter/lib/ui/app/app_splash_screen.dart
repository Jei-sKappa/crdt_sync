import 'package:example_flutter/ui/todo/todo.dart';
import 'package:flutter/material.dart';

class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen> {
  bool _isInitialized = false;

  Future<void> _initializeApp() async {
    try {
      await Future.wait([
        Future<void>.delayed(const Duration(milliseconds: 300)),
      ]);
    } on Object catch (e, stackTrace) {
      debugPrint('Error while initializing app: $e\n$stackTrace');
    }

    _isInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    const nextScreen = TodoScreen();

    if (!_isInitialized) {
      return FutureBuilder(
        future: _initializeApp(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return nextScreen;
        },
      );
    }

    return nextScreen;
  }
}
