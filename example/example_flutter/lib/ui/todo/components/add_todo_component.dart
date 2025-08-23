import 'package:example_flutter/domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddTodoComponent extends StatefulWidget {
  const AddTodoComponent({super.key});

  @override
  State<AddTodoComponent> createState() => _AddTodoComponentState();
}

class _AddTodoComponentState extends State<AddTodoComponent> {
  final TextEditingController _newTodoController = TextEditingController();

  @override
  void dispose() {
    _newTodoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todoRepository = context.read<TodoRepository>();

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _newTodoController,
            decoration: InputDecoration(
              hintText: 'Add a new todo item',
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            onSubmitted: (text) async {
              final trimmed = text.trim();
              if (trimmed.isEmpty) return;
              await todoRepository.add(trimmed);
              _newTodoController.clear();
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 56,
          width: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: EdgeInsets.zero,
            ),
            onPressed: () async {
              final text = _newTodoController.text.trim();
              if (text.isEmpty) return;
              await todoRepository.add(text);
              _newTodoController.clear();
            },
            child: const Icon(Icons.add, size: 28),
          ),
        ),
      ],
    );
  }
}
