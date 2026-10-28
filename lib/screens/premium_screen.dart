import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/entitlement_service.dart';
import '../services/play_billing_service.dart';

/// Pantalla de membresía Zone Premium con facturación REAL de Google Play.
///
/// Diseño: docs/redesign/ZONE_FREEMIUM_ARCHITECTURE.md §2.6 y
/// docs/redesign/ZONE_PREMIUM_BILLING.md.
///
/// Reglas de honestidad implementadas:
///  - Los precios provienen SIEMPRE de `ProductDetails` reales de Play. Sin
///    datos de Play (owner pendiente de configurar Play Console), las tarjetas
///    muestran "Cargando…" y la compra está desactivada. NUNCA precios
///    inventados en el cliente.
///  - El éxito de Play NO activa Premium: tras `purchased` el estado queda en
///    "verificando…" hasta que el backend (z215 / edge function) confirme.
///  - El estado mostrado de membresía proviene de `EntitlementService`
///    (backend verificado, fail-closed).
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final PlayBillingService _billing = PlayBillingService.instance;
  final EntitlementService _entitlement = EntitlementService.instance;

  PremiumSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _billing.initialize();
    _loadEntitlement();
  }

  Future<void> _loadEntitlement() async {
    final snap = await _entitlement.load();
    if (mounted) setState(() => _snapshot = snap);
  }

  @override
  void dispose() {
    // El singleton de billing sobrevive a la pantalla; NO se hace dispose
    // aquí (la escucha de compras es global).
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Zone Premium',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MembershipHeader(snapshot: _snapshot),
              const SizedBox(height: 24),
              // Banner del flujo de facturación (estados exactos §2.5).
              ValueListenableBuilder<BillingUiState>(
                valueListenable: _billing.uiState,
                builder: (context, ui, _) {
                  if (ui.message == null || ui.message!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final isBad = ui.state == BillingState.error;
                  final isPending = ui.state == BillingState.verificationPending ||
                      ui.state == BillingState.pending ||
                      ui.state == BillingState.succeededUnverified;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isBad
                            ? Colors.redAccent.withValues(alpha: 0.6)
                            : isPending
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                                : const Color(0xFF00D2FF).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isBad
                              ? Icons.error_outline
                              : isPending
                                  ? Icons.hourglass_top
                                  : Icons.verified_outlined,
                          color: isBad
                              ? Colors.redAccent
                              : isPending
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF00D2FF),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            ui.message!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Tarjetas de plan con datos REALES de Play.
              ValueListenableBuilder<List<ProductDetails>>(
                valueListenable: _billing.products,
                builder: (context, products, _) {
                  final monthly = _find(products, ZoneBillingProducts.monthly);
                  final annual = _find(products, ZoneBillingProducts.annual);
                  return Column(
                    children: [
                      _PlanCard(
                        title: 'Mensual',
                        product: monthly,
                        icon: Icons.flash_on,
                        color: const Color(0xFF00D2FF),
                        onBuy: _buy,
                      ),
                      const SizedBox(height: 16),
                      _PlanCard(
                        title: 'Anual',
                        product: annual,
                        icon: Icons.diamond,
                        color: const Color(0xFF8B5CF6),
                        isRecommended: true,
                        onBuy: _buy,
                      ),
                      if (products.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Los planes se cargan desde Google Play. Si no '
                            'aparecen, la tienda aún no tiene esta app '
                            'configurada para compras.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _ActionRow(onRestore: _restore, onManage: _manageSubscriptions),
              const SizedBox(height: 24),
              const Text(
                'El radar y descubrimiento Bluetooth son funciones Premium. '
                'El descubrimiento por GPS es gratuito. Tu membresía se '
                'verifica en el servidor: la activación real puede tardar '
                'unos minutos después de la compra.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ProductDetails? _find(List<ProductDetails> products, String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _buy(ProductDetails product) {
    _billing.buyProduct(product);
  }

  void _restore() {
    _billing.restorePurchases();
    _loadEntitlement();
  }

  Future<void> _manageSubscriptions() async {
    await _billing.openSubscriptionManagement();
    if (mounted) _loadEntitlement();
  }
}

/// Encabezado con el estado REAL de membresía (backend verificado).
class _MembershipHeader extends StatelessWidget {
  const _MembershipHeader({required this.snapshot});

  final PremiumSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    final active = snap?.allowsBluetooth ?? false;
    final stateName = snap?.state ?? PremiumState.free;
    String subtitle = stateName.message;
    final expires = snap?.expiresAt;
    if (active && expires != null) {
      final local = expires.toLocal();
      subtitle =
          '$subtitle Vigente hasta ${local.day}/${local.month}/${local.year}.';
    }
    if (snap?.verifiedSource == 'transitional_legacy_is_premium') {
      subtitle =
          '$subtitle (modo de transición; se revalidará con el nuevo backend)';
    }
    return Container(
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
            active ? Icons.verified_user : Icons.workspace_premium_outlined,
            size: 48,
            color: active ? const Color(0xFF00D2FF) : Colors.white24,
          ),
          const SizedBox(height: 12),
          Text(
            active ? 'Eres Premium' : 'Desbloquea el Radar Bluetooth',
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de plan: precio SOLO desde `ProductDetails` real (R1/R9).
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.product,
    required this.icon,
    required this.color,
    required this.onBuy,
    this.isRecommended = false,
  });

  final String title;
  final ProductDetails? product;
  final IconData icon;
  final Color color;
  final void Function(ProductDetails) onBuy;
  final bool isRecommended;

  @override
  Widget build(BuildContext context) {
    final product = this.product;
    final hasProduct = product != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: isRecommended ? Border.all(color: color, width: 2) : null,
        boxShadow: isRecommended
            ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 10)]
            : null,
      ),
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
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text(
                  hasProduct
                      ? 'Suscripción automática'
                      : 'Cargando desde Google Play…',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            // Sin datos de Play → compra desactivada (jamás precio inventado).
            onPressed: hasProduct ? () => onBuy(product) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: Colors.white10,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              hasProduct ? product.price : '—',
              style: TextStyle(
                color: hasProduct ? Colors.black : Colors.white24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onRestore, required this.onManage});

  final VoidCallback onRestore;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onRestore,
            icon: const Icon(Icons.restore, color: Colors.white70, size: 18),
            label: const Text('Restaurar',
                style: TextStyle(color: Colors.white70)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.settings, color: Colors.white70, size: 18),
            label: const Text('Suscripciones',
                style: TextStyle(color: Colors.white70)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}
