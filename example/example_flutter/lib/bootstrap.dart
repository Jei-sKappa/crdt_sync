import 'package:example_flutter/domain/domain.dart';
import 'package:example_flutter/ui/app/app.dart';
import 'package:flutter/material.dart';

void bootstrap(TodoRepository todoRepository) {
  runApp(App(todoRepository: todoRepository));
}
