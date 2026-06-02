import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://leejpxwctnubihacudik.supabase.co',
    'sb_publishable_vl-aeN4Ior-GZ5YB45MFyA_KGxgfZjV'
  );

  try {
    final users = await supabase.from('users').select().limit(5);
    for (var _ in users) {
      // User data processing
    }
  } catch (e) {
    // Error handling
  }

  try {
    final msgs = await supabase.from('messages').select().order('created_at', ascending: false).limit(5);
    for (var _ in msgs) {
      // Message data processing
    }
  } catch (e) {
    // Error handling
  }
}
