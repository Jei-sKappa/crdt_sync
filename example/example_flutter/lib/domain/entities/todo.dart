class Todo {
  const Todo({required this.id, required this.title, required this.done});
  final String id;
  final String title;
  final bool done;

  Todo copyWith({String? id, String? title, bool? done}) => Todo(
    id: id ?? this.id,
    title: title ?? this.title,
    done: done ?? this.done,
  );
}
