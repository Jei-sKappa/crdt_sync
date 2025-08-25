import 'package:example_flutter/ui/auth/auth.dart';
import 'package:example_flutter/ui/todo/todo.dart';
import 'package:flutter/material.dart';

class TodoScreen extends StatelessWidget {
  const TodoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const UserLabelComponent(),
        actions: [
          LogOutButton(),
        ],
      ),
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
