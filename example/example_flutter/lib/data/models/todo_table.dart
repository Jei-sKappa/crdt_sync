import 'package:drift/drift.dart';
import 'package:drift_crdt/drift_crdt.dart';

@DataClassName('TodoModel')
class Todos extends Table with CrdtColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
