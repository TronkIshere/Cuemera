// core/services/supabase_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static const String _supabaseUrl = 'https://mavktsoseqbayknogoom.supabase.co';
  static const String _supabaseAnonKey =
      'sb_publishable_7XbO9W2wTPdVyl8yw4qUDw_wqTW0npq';

  static Future<void> initialize() {
    return Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseService.client;
});
