/// PHASE 2.2.4 — Canonical match pair (pure logic, no I/O).
///
/// PROBLEM: `matches` uniqueness was directional (`UNIQUE(requester,receiver)`),
/// so A→B and B→A created two rows; same-direction retry hit UNIQUE and
/// `requestMatch` returned null while the UI showed "pending" without matchId.
///
/// RULE (documented here and pinned by tests): a match between users A and B
/// has ONE canonical pair derived from the authoritative identifier already
/// used by the `matches` table (Supabase `users.id` UUIDs):
/// ```
/// canonicalLow  = min(A, B)   // lexicographic, deterministic
/// canonicalHigh = max(A, B)
/// canonical(A,B) == canonical(B,A)
/// ```
/// - No second identity protocol: no device IDs, no private keys, no
///   encounterKey (encounters are sightings, not relationships).
/// - `requester_id`/`receiver_id` REMAIN: direction still expresses who asked
///   and who may accept (RLS mirrors this). Canonicalization governs
///   uniqueness + lookup ONLY — never authorization (RLS is authoritative).
library;

/// Fail-closed error for match identity problems (empty/self identifiers).
class InvalidMatchIdentityError implements Exception {
  const InvalidMatchIdentityError(this.cause);

  final String cause;

  @override
  String toString() => 'InvalidMatchIdentityError: $cause';
}

/// Requested outcome of `requestMatch` after inspecting existing state.
enum MatchRequestAction {
  /// No logical match exists (or the rejected one was cleared): insert fresh.
  create,

  /// A logical match already exists: return it, never duplicate or downgrade.
  reuse,

  /// A rejected row blocks the pair: delete it, then insert fresh.
  recreate,
}

/// Pure decision for `requestMatch` (CASE 1–6 of PHASE 2.2.4):
/// - none → create.
/// - pending → reuse (no duplicate, no direction flip).
/// - accepted → reuse (never downgraded to pending).
/// - rejected → recreate (delete + fresh insert; matches the UI affordance
///   that offers "Conectar" again and the `deleteMatch` cascade precedent).
/// - unknown status → reuse (never duplicate on unreadable state).
/// - corrupt row without id → create (insert conflicts converge via recovery).
class MatchRequestDecision {
  const MatchRequestDecision._(this.action, this.matchId);

  final MatchRequestAction action;

  /// Existing (or doomed) match id for reuse/recreate; null for create.
  final String? matchId;

  static MatchRequestDecision create() =>
      const MatchRequestDecision._(MatchRequestAction.create, null);

  static MatchRequestDecision reuse(String matchId) =>
      MatchRequestDecision._(MatchRequestAction.reuse, matchId);

  static MatchRequestDecision recreate(String matchId) =>
      MatchRequestDecision._(MatchRequestAction.recreate, matchId);
}

/// Canonical pair + request/authorization decisions (all pure).
class MatchPair {
  MatchPair._();

  /// Validates a participant identifier (non-empty; self-pairs rejected by
  /// [canonicalLow]/[canonicalHigh] callers via [checkPair]).
  static String _check(String id, String role) {
    final v = id.trim();
    if (v.isEmpty) {
      throw InvalidMatchIdentityError('empty $role identifier');
    }
    return v;
  }

  /// Lower member of the canonical pair. Throws on empty/self identifiers.
  static String canonicalLow(String a, String b) {
    final x = _check(a, 'first');
    final y = _check(b, 'second');
    if (x == y) {
      throw const InvalidMatchIdentityError('self-match is not a match');
    }
    return x.compareTo(y) <= 0 ? x : y;
  }

  /// Upper member of the canonical pair. Throws on empty/self identifiers.
  static String canonicalHigh(String a, String b) {
    final x = _check(a, 'first');
    final y = _check(b, 'second');
    if (x == y) {
      throw const InvalidMatchIdentityError('self-match is not a match');
    }
    return x.compareTo(y) > 0 ? x : y;
  }

  /// Pure `requestMatch` decision from an existing canonical row (or null).
  static MatchRequestDecision decide({
    required Map<String, dynamic>? existing,
    required String requesterId,
    required String receiverId,
  }) {
    _check(requesterId, 'requester');
    _check(receiverId, 'receiver');
    if (requesterId.trim() == receiverId.trim()) {
      throw const InvalidMatchIdentityError('self-match is not a match');
    }
    if (existing == null) return MatchRequestDecision.create();
    final id = existing['id'] as String?;
    if (id == null || id.isEmpty) return MatchRequestDecision.create();
    switch (existing['status'] as String?) {
      case 'accepted':
        return MatchRequestDecision.reuse(id);
      case 'pending':
        return MatchRequestDecision.reuse(id);
      case 'rejected':
        return MatchRequestDecision.recreate(id);
      default:
        return MatchRequestDecision.reuse(id);
    }
  }

  /// Client-side mirrors of the RLS contract (RLS remains authoritative):
  /// only the receiver may accept/reject; any participant may read/delete.
  /// `me` is the authenticated uid performing the action.
  static bool isParticipant(Map<String, dynamic> row, String me) =>
      row['requester_id'] == me || row['receiver_id'] == me;

  static bool canAccept(Map<String, dynamic> row, String me) =>
      row['receiver_id'] == me;

  static bool canReject(Map<String, dynamic> row, String me) =>
      row['receiver_id'] == me;

  /// UI-state safety (NULL matchId bug): pending is shown ONLY with a valid
  /// identifier. A null/empty result must keep/reset state to idle (0) with
  /// an error — never fabricate pending.
  static bool isValidMatchId(String? matchId) =>
      matchId != null && matchId.trim().isNotEmpty;
}
