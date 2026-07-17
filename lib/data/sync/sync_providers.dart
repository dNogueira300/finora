import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/database.dart';

// Task 13 extendera este archivo con el motor de sincronizacion.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
