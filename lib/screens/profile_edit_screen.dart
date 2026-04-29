import 'package:flutter/material.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  _ProfileEditScreenState createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final TextEditingController _nameController = TextEditingController(text: 'Mi Perfil');
  final TextEditingController _igController = TextEditingController(text: '@dybro');
  
  bool _isIgVisible = true;

  @override
  void dispose() {
    _nameController.dispose();
    _igController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Editar Mi Perfil'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.black45,
                  child: Icon(Icons.person, size: 50, color: Colors.white54),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF00D2FF),
                  ),
                  child: const Icon(Icons.edit, color: Colors.black, size: 20),
                )
              ],
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Nombre público',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00D2FF))),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _igController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Instagram',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00D2FF))),
                prefixIcon: const Icon(Icons.camera_alt, color: Colors.white54),
              ),
            ),
            SwitchListTile(
              title: const Text('Visible para los demás en el Radar', style: TextStyle(color: Colors.white70)),
              value: _isIgVisible,
              activeColor: const Color(0xFF00D2FF),
              onChanged: (val) => setState(() => _isIgVisible = val),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D2FF),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Preferencias actualizadas con éxito.', style: TextStyle(color: Colors.white))),
                );
              },
              child: const Text('Guardar Configuración', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        ),
      ),
    );
  }
}
