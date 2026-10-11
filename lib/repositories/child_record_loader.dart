import 'package:sqflite/sqflite.dart';

/// Loads children only for already owner-filtered parent IDs. Bounded IN lists
/// stay below SQLite's parameter limit; every parent's children retain the
/// repository's existing order, even when the parent list spans several chunks.
Future<Map<String, List<Map<String, dynamic>>>> loadChildRecords(
  DatabaseExecutor database, {
  required String table,
  required String parentColumn,
  required Iterable<String> parentIds,
  required String orderBy,
}) async {
  final ids = parentIds.toSet().toList(growable: false);
  final grouped = <String, List<Map<String, dynamic>>>{};
  const chunkSize = 400;
  for (var offset = 0; offset < ids.length; offset += chunkSize) {
    final chunk = ids.skip(offset).take(chunkSize).toList(growable: false);
    final rows = await database.query(
      table,
      where: '$parentColumn IN (${List.filled(chunk.length, '?').join(',')})',
      whereArgs: chunk,
      orderBy: orderBy,
    );
    for (final row in rows) {
      (grouped[row[parentColumn] as String] ??= []).add(
        Map<String, dynamic>.from(row),
      );
    }
  }
  return grouped;
}
