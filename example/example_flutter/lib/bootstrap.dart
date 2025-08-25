import 'package:crdt/crdt.dart';
import 'package:example_flutter/domain/domain.dart';
import 'package:example_flutter/ui/app/app.dart';
import 'package:flutter/material.dart';

void bootstrap({
  required Crdt crdt,
  required AuthRepository authRepository,
  required TodoRepository todoRepository,
}) {
  runApp(
    App(
      crdt: crdt,
      authRepository: authRepository,
      todoRepository: todoRepository,
    ),
  );
}
