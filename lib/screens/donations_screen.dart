import 'package:flutter/material.dart';
import '../services/entitlement_service.dart';
import 'premium_screen.dart';

/// Pantalla de apoyo/donaciones.
///
/// **Refactor freemium:** la compra SIMULADA anterior
/// (`_buyPremium(plan, price)` → `setPremium(true)`) fue eliminada. Las
/// donaciones NO conceden Premium: la membresía real se compra en
/// [PremiumScreen] con Google Play y se verifica en el backend
/// (`EntitlementService`, fail-closed · docs/redesign/ZONE_PREMIUM_BILLING.md).
class DonationsScreen extends StatefulWidget {
  const DonationsScreen({super.key});

  @override
  State<DonationsScreen> createState() => _DonationsScreenState();
}

class _DonationsScreenState extends State<DonationsScreen> {
  PremiumSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    // Estado REAL de membresía (backend verificado; sin flags locales).
    final snap = await EntitlementService.instance.load();
    if (mounted) setState(() => _snapshot = snap);
  }

  @override
  Widget build(BuildContext context) {
    final active = _snapshot?.allowsBluetooth ?? false;
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Apoya Zone', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: active ? const Color(0xFF00D2FF) : Colors.white10),
              ),
              child: Column(
                children: [
                  Icon(
                    active ? Icons.verified_user : Icons.favorite,
                    size: 48,
                    color: active ? const Color(0xFF00D2FF) : Colors.white24,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    active ? 'Eres Premium' : 'Apoya el desarrollo de Zone',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    active
                        ? 'Tu membresía está activa y verificada.'
                        : 'Zone es gratuito. El radar Bluetooth es la función '
                            'Premium; el descubrimiento por GPS es gratis.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Zone se mantiene independiente. Si quieres apoyar el '
              'desarrollo, la membresía Premium es la forma oficial: '
              'desbloquea el radar Bluetooth y financia el proyecto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                );
              },
              icon: const Icon(Icons.workspace_premium, color: Colors.black),
              label: const Text(
                'Ver membresía Premium',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D2FF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Las donaciones directas no otorgan beneficios ni membresía: '
              'el acceso Premium se activa únicamente cuando el servidor '
              'verifica una compra real de Google Play.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
