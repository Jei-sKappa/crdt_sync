import 'package:example_flutter/domain/domain.dart';

abstract class TodoRepository {
  Stream<List<Todo>> watchTodos();
  Future<void> add(String title);
  Future<void> toggleDone(String id);
  Future<void> delete(String id);
}
