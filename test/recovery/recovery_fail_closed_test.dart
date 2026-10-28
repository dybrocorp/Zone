///PHASE G — login fail-closed tests (regras R-13 / R-05).
///
/// Two layers:
/// 1. PURE UNIT (executable in VM): `LoginRecoveryPolicy` (format, corruption
///    classification, typed errors) — real behavioral coverage.
/// 2. SOURCE CONTRACT SCAN: assert the frozen order of `loginWithExistingID`
///    (policy → format → signIn → RPC → persist → ensureAuth → commit) and
///    that `deleteAll()` does NOT exist in the login/recovery paths
///    (`getOrCreate`, `loginWithExistingID`, `_loginWithExistingIDInternal`).
///    Precedent: `test/sql_security_regression_test.dart` (textual source scan
///    as contract). The pure part tests the REAL behavior; the scan locks in
///    the ordering, which is not testable in a VM (ZoneIdService requires
///    initialized Supabase at construction).
///
/// Label: LOCALLY TESTED (units + source contract; no backend).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zone/services/login_recovery_policy.dart';
import 'package:zone/services/same_account_claim_policy.dart';

void main() {
  final serviceSource = File(
    'lib/services/zone_id_service.dart',
  ).readAsStringSync();

  group('LoginRecoveryPolicy (pure module) — format validation', () {
    test('valid canonical ZONE-IDs', () {
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('ZONE-ABCD1234'), isTrue);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('ZONE-00000000'), isTrue);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('ZONE-ZZZZZZZZ'), isTrue);
    });

    test('invalid (fail-closed without side effects)', () {
      expect(LoginRecoveryPolicy.isValidZoneIdFormat(null), isFalse);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat(''), isFalse);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('ZONE-ABC'), isFalse);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('ZONE-ABCD12345'), isFalse);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('ZONE-abcd1234'), isFalse);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('ZONE-ABCD 123'), isFalse);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('ZONE-ABCD_123'), isFalse);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('ZONE-'), isFalse);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('ABCD1234'), isFalse);
      expect(LoginRecoveryPolicy.isValidZoneIdFormat('zone-ABCD1234'), isFalse);
    });
  });

  group('LoginRecoveryPolicy — corruption classification (rule R-05)', () {
    test('known keystore signals classify as corruption', () {
      expect(
        LoginRecoveryPolicy.isStorageCorruptionSignal(
          Exception('javax.crypto.BadPaddingException while decrypting'),
        ),
        isTrue,
      );
      expect(
        LoginRecoveryPolicy.isStorageCorruptionSignal(
          Exception('Error during decryption of SecureStorage value'),
        ),
        isTrue,
      );
    });

    test('other errors are NOT classified as corruption', () {
      expect(
        LoginRecoveryPolicy.isStorageCorruptionSignal(
          Exception('No se pudo establecer sesión anónima.'),
        ),
        isFalse,
      );
      expect(
        LoginRecoveryPolicy.isStorageCorruptionSignal(
          Exception('RLS policy violation'),
        ),
        isFalse,
      );
      expect(
        LoginRecoveryPolicy.isStorageCorruptionSignal(FormatException('x')),
        isFalse,
      );
    });

    test('the policy ALWAYS decides to fail-closed (never deletes)', () {
      // R-05: there is no corruption case in which the "recovery" is to
      // delete the entire storage; the recovery is a typed error/rethrow.
      expect(
        LoginRecoveryPolicy.shouldFailClosedOnCorruption(
          Exception('BadPaddingException'),
        ),
        isTrue,
      );
    });
  });

  group('Typed errors: no secret information leaks (UI-safe)', () {
    test('StorageCorruptionError', () {
      const err = StorageCorruptionError('loginWithExistingID');
      final text = err.toString();
      expect(text, contains('StorageCorruptionError'));
      expect(text, contains('corrupto'));
      // UI-safe invariants: never contains key material patterns.
      expect(text.contains('BEGIN PRIVATE KEY'), isFalse);
      //Does not echo the raw origin (it may contain ciphertext).
      expect(text.contains('origin'), isFalse);
    });

    test('LoginFormatError', () {
      const err = LoginFormatError();
      final text = err.toString();
      expect(text, contains('ZONE-XXXXXXXX'));
    });
  });

  group('SameAccountClaimPolicy — guard runs FIRST (without side effects)', () {
    setUp(() {
      SameAccountClaimPolicy.allowSameAccountClaim = false;
    });
    tearDown(() {
      SameAccountClaimPolicy.allowSameAccountClaim = false;
    });

    test('quarantined by default', () {
      expect(SameAccountClaimPolicy.allowSameAccountClaim, isFalse);
      expect(
        () => SameAccountClaimPolicy.ensureAllowed('ZONE-ABCD1234'),
        throwsA(isA<SameAccountClaimBlockedError>()),
      );
    });
  });

  group('SOURCE CONTRACT SCAN (zone_id_service.dart)', () {
    /// Extracts the text of an entire method delimited by its signature until
    /// the signature of the next structural marker, WITHOUT doc/block and //
    /// comments (the contract examines code, not prose).
    String extractMethod(String signature, String endOfRange) {
      final startIdx = serviceSource.indexOf(signature);
      expect(startIdx, greaterThanOrEqualTo(0),
          reason: 'signature not found: $signature');
      final endIdx = startIdx == -1
          ? -1
          : serviceSource.indexOf(endOfRange, startIdx + 1);
      expect(endIdx, greaterThan(startIdx),
          reason: 'end marker not found: $endOfRange');
      final region = serviceSource.substring(startIdx, endIdx);
      final codeOnly = region
          .split('\n')
          .where(
            (line) => !line.trimLeft().startsWith('//'),
          )
          .join('\n');
      return codeOnly;
    }

    test('frozen order of login: policy → format → signIn → RPC → persist',
        () {
      final login = extractMethod(
        'Future<bool> loginWithExistingID(',
        'Future<void> _registerInSupabase()',
      );

      final idxPolicy = login.indexOf('SameAccountClaimPolicy.ensureAllowed');
      final idxFormat = login.indexOf('isValidZoneIdFormat(zoneId)');
      final idxSignIn = login.indexOf('signInAnonymously');
      final idxRpc = login.indexOf('claim_zone_id');
      final idxPersist = login.indexOf("key: _keyZoneId");

      expect(idxPolicy, greaterThanOrEqualTo(0));
      expect(idxFormat, greaterThan(idxPolicy),
          reason: 'R-13: format validation AFTER policy, BEFORE signIn');
      expect(idxSignIn, greaterThan(idxFormat),
          reason: 'R-13: anonymous session AFTER format is valid');
      expect(idxRpc, greaterThan(idxSignIn));
      expect(idxPersist, greaterThan(idxRpc),
          reason: 'local persistence AFTER successful claim');
    });

    test('R-05: no deleteAll() in recovery/login paths', () {
      final getOrCreate = extractMethod(
        'Future<String> getOrCreate() async {',
        'Future<String> _getOrCreateInternal() async {',
      );
      expect(getOrCreate.contains('deleteAll'), isFalse,
          reason: 'getOrCreate must not delete everything on corruption');

      final login = extractMethod(
        'Future<bool> loginWithExistingID(',
        'Future<void> _registerInSupabase()',
      );
      expect(login.contains('deleteAll'), isFalse,
          reason: 'login must not delete everything on corruption '
              '(R-13/R-05 defect committed)');
    });

    test('login commits in-memory identity AFTER persistence', () {
      final login = extractMethod(
        'Future<bool> loginWithExistingID(',
        'Future<void> _registerInSupabase()',
      );
      final idxPersist = login.indexOf("key: _keyZoneId");
      final idxCommit = login.indexOf('_zoneId = zoneId;');
      expect(idxCommit, greaterThan(idxPersist),
          reason: 'the singleton commits only with all effects made (step 7)');
    });

    test('restores in-memory previous state on general failure', () {
      final login = extractMethod(
        'Future<bool> loginWithExistingID(',
        'Future<void> _registerInSupabase()',
      );
      expect(login.contains('previousZoneId'), isTrue);
      expect(login.contains('previousUid'), isTrue);
    });

    test('corruption is re-thrown TYPIED (StorageCorruptionError)', () {
      final login = extractMethod(
        'Future<bool> loginWithExistingID(',
        'Future<void> _registerInSupabase()',
      );
      expect(
        login.contains(RegExp(r'StorageCorruptionError\(')),
        isTrue,
        reason: 'login must throw typed error, not deleteAll',
      );
      final getOrCreate = extractMethod(
        'Future<String> getOrCreate() async {',
        'Future<String> _getOrCreateInternal() async {',
      );
      expect(
        getOrCreate.contains(RegExp(r'StorageCorruptionError\(')),
        isTrue,
      );
    });

    test('getOrCreate no longer retries the flow after "corruption"', () {
      final getOrCreate = extractMethod(
        'Future<String> getOrCreate() async {',
        'Future<String> _getOrCreateInternal() async {',
      );
      // EXACTLY ONE call to the internal flow is permitted (the normal one);
      // the old re-call after deleteAll repeated side effects (login).
      final callCount =
          RegExp('_getOrCreateInternal\\(').allMatches(getOrCreate).length;
      expect(callCount, 1);
    });

    test('delegated format: both authorities use the same pattern', () {
      // The DeepLinkZones shared contract: the ONLY ^ZONE-[A-Z0-9]{8}$ regex
      // must live in the pure module.
      expect(
        serviceSource.contains(RegExp(r'zoneId\s*==\s*null'
            r'\s*\?\?\s*[^;]+RegExp')) ||
            serviceSource.contains('LoginRecoveryPolicy.isValidZoneIdFormat'),
        isTrue,
        reason: 'isValidZoneIdFormat delegates to the pure module',
      );
      // The full regex must NOT be re-declared in the service (a single truth).
      expect(
        serviceSource.contains(r"RegExp(r'^ZONE-[A-Z0-9]{8}$')"),
        isFalse,
        reason: 'duplicate canonical pattern forbidden (single source of truth)',
      );
    });
  });
}
