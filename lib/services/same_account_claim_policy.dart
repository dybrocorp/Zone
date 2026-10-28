/// PHASE 2.2.2 — Quarantine of the unsafe same-account Device B claim.
///
/// PRODUCT SAFETY GATE (not cryptography, not migration):
/// until the account/device bridge exists (possession proof + `register_device`
/// with account/device signatures, 2.2.3+), NO device may claim another
/// device's `ZONE-XXXXXXXX` handle via `loginWithExistingID` → `claim_zone_id`.
///
/// Why: knowledge of the handle (`ZONE-ID` visible in the P2P mesh) is not
/// possession. Claiming it today creates a split-brain — the SAME legacy
/// `zone_id` handle behind TWO different foundation identities (different
/// `account_id`, different `device_id`, different X25519 private key).
///
/// Temporary product rule: NEW DEVICE = NEW ACCOUNT.
///
/// - [SameAccountClaimPolicy.allowSameAccountClaim] is the single kill-switch.
///   Default `false`. Only the future bridge may set it to `true`.
/// - [SameAccountClaimPolicy.ensureAllowed] is fail-closed and side-effect
///   free: it runs BEFORE any Supabase sign-in, storage write, RPC or key
///   generation. Callers must invoke it as the FIRST statement.
/// - [SameAccountClaimBlockedError] is the explicit migration-not-available
///   state surfaced to the UI. It carries no secret material.
library;

/// Fail-closed error: same-account claim attempted while the account/device
/// bridge (possession proof) is not yet available.
///
/// Message is UI-safe: handle format hint + what the user must do instead.
/// Never contains keys, seeds, tokens or identifiers beyond the typed handle.
class SameAccountClaimBlockedError implements Exception {
  const SameAccountClaimBlockedError(this.zoneId);

  final String zoneId;

  @override
  String toString() =>
      'SameAccountClaimBlockedError: no se puede usar $zoneId en este '
      'dispositivo. La migración de cuenta aún no está disponible: crea una '
      'cuenta nueva con "Comenzar".';
}

/// Single kill-switch for the legacy same-account claim path.
///
/// PHASE 2.2.2: `false` (quarantined). The future account/device bridge
/// (2.2.3+) is the ONLY code allowed to set this to `true`, and only after
/// possession-proof verification exists end to end.
class SameAccountClaimPolicy {
  SameAccountClaimPolicy._();

  static bool allowSameAccountClaim = false;

  /// Throws [SameAccountClaimBlockedError] while quarantined. Pure check:
  /// no I/O, no storage, no network — safe to call first, safe to test.
  static void ensureAllowed(String zoneId) {
    if (!allowSameAccountClaim) {
      throw SameAccountClaimBlockedError(zoneId);
    }
  }
}
