import 'package:supabase_flutter/supabase_flutter.dart';

bool get supabaseReady {
  try {
    Supabase.instance.client;
    return true;
  } catch (_) {
    return false;
  }
}

SupabaseClient get supabase {
  try {
    return Supabase.instance.client;
  } catch (_) {
    throw StateError('Supabase 未初始化，请配置 SUPABASE_URL 和 SUPABASE_ANON_KEY');
  }
}
