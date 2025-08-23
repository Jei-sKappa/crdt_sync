import 'package:drift/drift.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:example_flutter/core/utils/uuid.dart';
import 'package:example_flutter/data/data.dart';
import 'package:example_flutter/domain/domain.dart';

class SqliteCrdtTodoRepository implements TodoRepository {
  SqliteCrdtTodoRepository(this.crdt)
      : assert(
          crdt.isInitialized,
          'Crdt must be initialized using DriftCrdt.init() before using this '
          'repository.',
        );

  final DriftCrdt<AppDatabase> crdt;

  @override
  Stream<List<Todo>> watchTodos() {
    return crdt
        .watch(crdt.db.todos)
        .map((models) => models.map((e) => e.toEntity()).toList());
  }

  @override
  Future<void> add(String title) async {
    await crdt.write(
      (w) => w.insertOnConflictUpdate(
        crdt.db.todos,
        Todo(id: uuid.v4(), title: title, done: false).toInsertable(),
      ),
    );
  }

  @override
  Future<void> toggleDone(String id) async {
    final row = await (crdt.db.select(crdt.db.todos)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await crdt.write(
      (w) => w.update(
        crdt.db.todos,
        TodosCompanion(done: Value(!row.done)),
        where: (t) => [t.id.equals(id)],
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    await crdt.write(
      (w) => w.delete(crdt.db.todos, where: (t) => [t.id.equals(id)]),
    );
  }
}
