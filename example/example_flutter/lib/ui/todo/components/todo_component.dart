import 'package:example_flutter/domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TodoComponent extends StatelessWidget {
  const TodoComponent({required this.todo, super.key});

  final Todo todo;

  @override
  Widget build(BuildContext context) {
    final todoRepository = context.read<TodoRepository>();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Checkbox(
              value: todo.done,
              onChanged: (_) {
                todoRepository.toggleDone(todo.id);
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
              activeColor: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                todo.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      decoration: todo.done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color: todo.done
                          ? Theme.of(
                              context,
                            ).textTheme.bodyMedium?.color?.withAlpha(120)
                          : null,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.delete, color: Colors.white),
                onPressed: () {
                  todoRepository.delete(todo.id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
