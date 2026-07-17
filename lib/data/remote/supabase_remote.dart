import 'package:supabase_flutter/supabase_flutter.dart';
import 'remote_source.dart';

class SupabaseRemote implements RemoteSource {
  SupabaseRemote(this._client);
  final SupabaseClient _client;

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSince(String table, DateTime? since) async {
    var query = _client.from(table).select();
    if (since != null) {
      return List<Map<String, dynamic>>.from(
          await query.gt('updated_at', since.toUtc().toIso8601String()));
    }
    return List<Map<String, dynamic>>.from(await query);
  }
}
