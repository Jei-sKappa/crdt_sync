import 'package:example_flutter/domain/domain.dart';
import 'package:example_flutter/ui/todo/components/components.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TodoListComponent extends StatelessWidget {
  const TodoListComponent({super.key});

  @override
  Widget build(BuildContext context) {
    final todoRepository = context.read<TodoRepository>();

    return Expanded(
      child: StreamBuilder<List<Todo>>(
        stream: todoRepository.watchTodos(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final todos = snapshot.data ?? const <Todo>[];
          if (todos.isEmpty) {
            return const Center(child: Text('No todos'));
          }

          return ListView.builder(
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TodoComponent(todo: todo),
              );
            },
          );
        },
      ),
    );
  }
}
