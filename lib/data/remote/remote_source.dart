abstract class RemoteSource {
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);
  Future<List<Map<String, dynamic>>> fetchSince(String table, DateTime? since);
}
