import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://leejpxwctnubihacudik.supabase.co',
    'sb_publishable_vl-aeN4Ior-GZ5YB45MFyA_KGxgfZjV'
  );

  print('Intentando obtener la tabla de usuarios (puede fallar por RLS):');
  try {
    final users = await supabase.from('users').select().limit(5);
    for (var u in users) {
      print('User: ${u['zone_id']} | PubKey len: ${u['public_key'].toString().length}');
    }
  } catch (e) {
    print('RLS Users Error: $e');
  }

  print('\nIntentando leer la tabla de mensajes (saltando por API anónima, puede fallar):');
  try {
    final msgs = await supabase.from('messages').select().order('created_at', ascending: false).limit(5);
    for (var m in msgs) {
      print('Msg: ${m['id']}');
      print('   Enc: ${m['encrypted_content'].toString().length} chars');
      print('   Nonce: ${m['nonce'].toString().length} chars => ${m['nonce']}');
      print('   Mac: ${m['mac'].toString().length} chars => ${m['mac']}');
    }
  } catch (e) {
    print('RLS Messages Error: $e');
  }
}
