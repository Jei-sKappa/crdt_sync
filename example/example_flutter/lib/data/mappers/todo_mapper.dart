import 'package:drift/drift.dart';
import 'package:example_flutter/data/data.dart';
import 'package:example_flutter/domain/domain.dart';

extension TodoMapperExtension on Todo {
  TodosCompanion toInsertable() {
    return TodosCompanion(
      id: Value(id),
      title: Value(title),
      done: Value(done),
      isDeleted: const Value(false),
    );
  }
}

extension TodoEntityMapperExtension on TodoModel {
  Todo toEntity() {
    return Todo(id: id, title: title, done: done);
  }
}
