import 'package:flutter/material.dart';
import '../services/premium_service.dart';
import '../config/radar_config.dart';

class DonationsScreen extends StatefulWidget {
  const DonationsScreen({super.key});

  @override
  State<DonationsScreen> createState() => _DonationsScreenState();
}

class _DonationsScreenState extends State<DonationsScreen> {
  final PremiumService _premiumService = PremiumService.instance;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await _premiumService.loadPremiumStatus();
    if (mounted) setState(() => _isPremium = status);
  }

  void _buyPremium(String plan, int price) async {
    // Implementación simulada de compra
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Suscribirse a $plan', style: const TextStyle(color: Colors.white)),
        content: Text('¿Deseas activar el plan de \$${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              await _premiumService.setPremium(true);
              if (mounted) {
                Navigator.pop(dialogContext);
                _loadStatus();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('¡Gracias por tu apoyo! Ahora eres Zone Premium.'),
                    backgroundColor: Color(0xFF00D2FF),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D2FF)),
            child: const Text('Confirmar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Membresías Zone', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            _buildMembershipCard(
              title: '1 Mes',
              price: 15000,
              description: 'Prueba la experiencia completa',
              icon: Icons.flash_on,
              color: const Color(0xFF00D2FF),
            ),
            _buildMembershipCard(
              title: '3 Meses',
              price: 30000,
              description: 'Popular · Ahorra un 33%',
              icon: Icons.star,
              color: const Color(0xFF3A7BD5),
              isRecommended: true,
            ),
            _buildMembershipCard(
              title: '6 Meses',
              price: 70000,
              description: 'Ideal para usuarios activos',
              icon: Icons.workspace_premium,
              color: const Color(0xFF8B5CF6),
            ),
            _buildMembershipCard(
              title: '1 Año',
              price: 100000,
              description: 'Mejor valor · Soporte total',
              icon: Icons.diamond,
              color: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 48),
            Text(
              'Al adquirir una membresía eliminas el límite de ${RadarConfig.maxFreeDiscoveryRadiusMeters.round()} metros en el radar y apoyas el desarrollo de Zone.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _isPremium ? const Color(0xFF00D2FF) : Colors.white10),
      ),
      child: Column(
        children: [
          Icon(
            _isPremium ? Icons.verified_user : Icons.unarchive_outlined,
            size: 48,
            color: _isPremium ? const Color(0xFF00D2FF) : Colors.white24,
          ),
          const SizedBox(height: 12),
          Text(
            _isPremium ? '¡Eres Premium!' : 'Desbloquea el Radar',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            _isPremium 
              ? 'Disfrutas de alcance ilimitado' 
              : 'La versión gratuita está limitada a ${RadarConfig.maxFreeDiscoveryRadiusMeters.round()} metros',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipCard({
    required String title,
    required int price,
    required String description,
    required IconData icon,
    required Color color,
    bool isRecommended = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: isRecommended ? Border.all(color: color, width: 2) : null,
        boxShadow: isRecommended ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 10)] : null,
      ),
      child: InkWell(
        onTap: () => _buyPremium(title, price),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
                    style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Text('COP', style: TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
