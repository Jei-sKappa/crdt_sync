import 'package:example_flutter/ui/todo/components/components.dart';
import 'package:example_flutter/ui/todo/widgets/widgets.dart';
import 'package:flutter/material.dart';

class TodoScreen extends StatelessWidget {
  const TodoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SearchBarComponent(),
            AllTodosLabel(),
            TodoListComponent(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(left: 16, top: 8, right: 16, bottom: 16),
          child: AddTodoComponent(),
        ),
      ),
    );
  }
}
