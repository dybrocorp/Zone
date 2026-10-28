/// PHASE 2.2.3 — Canonical encounter identity (idempotency key).
///
/// PROBLEM: encounters were unilateral rows (`user_id`, `other_zone_id`,
/// `seen_at`) with only a per-direction hourly DB dedup. A↔B produced two
/// independent rows and rapid rediscovery produced unbounded rows.
///
/// STRATEGY (no new identity protocol — reuses existing authenticated
/// identifiers): both devices know BOTH `ZONE-XXXXXXXX` handles once the peer
/// is resolved (`users.zone_id` is `UNIQUE NOT NULL`; the discovery token is
/// ephemeral and MUST NOT be part of the key; foundation account/device ids
/// are NOT yet on the encounter path and are NOT required).
///
/// Formula (documented here and pinned by tests):
/// ```
/// norm(z)      = trim + UPPERCASE, must match ^ZONE-[A-Z0-9]{8}$ else fail-closed
/// pair         = sort([norm(zoneA), norm(zoneB)])   // deterministic order,
///                                                   // independent of who saw whom
/// bucket       = UTC hour of seenAt ('yyyyMMddHH')  // matches the existing
///                                                   // DB hourly dedup semantics
/// material     = 'ZEN-1' | pair[0] | pair[1] | bucket
/// encounter_key = 'ZEN-1:' + hex(sha256(material))
/// ```
/// Properties:
/// - A→B and B→A derive the SAME key (sorted pair, coarse UTC bucket).
/// - Stateless: recomputable after restart from persisted fields.
/// - Offline-first: pure local derivation, zero I/O.
/// - No private material in inputs (public handles + bucket label only); the
///   output is a fixed `ZEN-1:<64 hex>` identifier, structurally unable to
///   embed secrets. It is an identifier, NOT a credential: it grants no access
///   (RLS still binds `user_id = auth.uid()`) and cannot impersonate a device
///   (no signatures, no auth decisions keyed off it).
/// - Fail-closed: malformed handles or self-pair throw
///   [InvalidEncounterIdentityError]; [tryCanonicalKey] maps that to `null`
///   so callers skip the encounter (best-effort analytics must never crash
///   the radar).
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'zone_id_service.dart';

/// Fail-closed error for encounter identity problems (malformed handle,
/// self-pair). Carries only the public handle shape, never key material.
class InvalidEncounterIdentityError implements Exception {
  const InvalidEncounterIdentityError(this.cause);

  final String cause;

  @override
  String toString() => 'InvalidEncounterIdentityError: $cause';
}

/// Canonical encounter identity + local bucket-dedup decision (pure logic).
class EncounterKey {
  EncounterKey._();

  /// Protocol version prefix. Bump ONLY with a migration of stored keys.
  static const String protocolVersion = 'ZEN-1';

  /// Bucket width in hours. 1h mirrors the existing DB hourly dedup
  /// (`idx_unique_encounter_hourly`); distinct buckets are distinct logical
  /// encounters, repeated sightings in one bucket are one logical encounter.
  static const int bucketHours = 1;

  /// Normalizes a ZONE-ID handle (trim + uppercase) or throws fail-closed.
  static String normalize(String zoneId) {
    final normalized = zoneId.trim().toUpperCase();
    if (!ZoneIdService.isValidZoneIdFormat(normalized)) {
      throw InvalidEncounterIdentityError(
        'malformed zone handle (expected ZONE-XXXXXXXX)',
      );
    }
    return normalized;
  }

  /// UTC hour bucket containing [seenAt] (truncation, never rounding).
  static DateTime hourBucketUtc(DateTime seenAt) {
    final u = seenAt.toUtc();
    final bucketMillis =
        u.millisecondsSinceEpoch -
        (u.millisecondsSinceEpoch % (bucketHours * 3600000));
    return DateTime.fromMillisecondsSinceEpoch(bucketMillis, isUtc: true);
  }

  /// Bucket label `yyyyMMddHH` (UTC) embedded in the key material.
  static String bucketLabel(DateTime seenAt) {
    final u = seenAt.toUtc();
    String pad(int v, int w) => v.toString().padLeft(w, '0');
    return '${pad(u.year, 4)}${pad(u.month, 2)}${pad(u.day, 2)}${pad(u.hour, 2)}';
  }

  /// Derives the canonical encounter key for the unordered pair
  /// {zoneA, zoneB} in the hour bucket of [seenAt]. Order-independent.
  static Future<String> canonicalKey({
    required String zoneA,
    required String zoneB,
    required DateTime seenAt,
  }) async {
    final a = normalize(zoneA);
    final b = normalize(zoneB);
    if (a == b) {
      throw const InvalidEncounterIdentityError(
        'self-encounter is not a logical encounter',
      );
    }
    final pair = [a, b]..sort();
    final material =
        '$protocolVersion|${pair[0]}|${pair[1]}|${bucketLabel(seenAt)}';
    final digest = await Sha256().hash(utf8.encode(material));
    return '$protocolVersion:${_hex(digest.bytes)}';
  }

  /// Non-throwing wrapper: `null` means "skip this encounter" (fail-closed).
  static Future<String?> tryCanonicalKey({
    required String myZone,
    required String peerZone,
    required DateTime seenAt,
  }) async {
    try {
      return await canonicalKey(zoneA: myZone, zoneB: peerZone, seenAt: seenAt);
    } on InvalidEncounterIdentityError {
      return null;
    }
  }

  /// Local dedup decision over already-persisted sighting timestamps of the
  /// SAME pair: `true` when [candidate] falls in an already-recorded bucket.
  /// Restart-safe (operates on persisted `seenAt` values) and offline-safe
  /// (no I/O of its own; the store query runs in the caller's transaction).
  static bool isDuplicate({
    required List<DateTime> existingSeenAt,
    required DateTime candidate,
  }) {
    final bucket = hourBucketUtc(candidate);
    return existingSeenAt.any((s) => hourBucketUtc(s) == bucket);
  }

  static String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
