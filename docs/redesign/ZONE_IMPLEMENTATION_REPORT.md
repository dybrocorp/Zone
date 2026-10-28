# Laporan Implementasi — Redesain Freemium Zone

**Tanggal:** 28 Oktober 2026
**Basis:** `main` @ `1bf6e1b75f488e4b5d023fcf9183b8299e704639` (origin/main)
**Lingkup:** Tahap A (audit + desain) dan Tahap B (implementasi GPS+Red gratis, radar Bluetooth Premium).

---

## A. Baseline & Perlindungan Repo

| Butir | Status | Bukti |
|---|---|---|
| Baseline `main` terkunci sebelum perubahan | **PASS** | `1bf6e1b75f488e4b5d023fcf9183b8299e704639`, sinkron dengan origin |
| 3 PNG evidence owner tidak tersentuh | **PASS** | `docs/device_lab/evidence/SERVER_CONFIG_auth_screen.png`, `SERVER_CONFIG_final_state.png`, `WIRING_identity_bootstrap_R01.png` tetap di staging, tidak dimodifikasi, dan **dikecualikan dari commit** (commit pathspec-only) |
| Tanpa operasi git destruktif | **PASS** | Tidak ada reset/checkout file/force push; hanya edit file baru/tertarget |
| Tanpa rahasia di commit/output | **PASS** | `.env`, keystores, kredensial tidak pernah dibaca ke output maupun disertakan; `git diff --check` bersih (exit 0) |
| Tanpa APK di dalam repo | **PASS** | APK hanya di `build/` (diabaikan git) |

## B. Tahap A — Dokumen Desain

| Dokumen | Status |
|---|---|
| `docs/redesign/ZONE_FREEMIUM_ARCHITECTURE.md` | **PASS** |
| `docs/redesign/ZONE_DISCOVERY_PRIVACY.md` | **PASS** |
| `docs/redesign/ZONE_PREMIUM_BILLING.md` | **PASS** |
| `docs/redesign/ZONE_DATA_MIGRATION.md` | **PASS** |
| `docs/redesign/ZONE_ACCEPTANCE_TESTS.md` | **PASS** (matriks L/D/P menjadi dasar test baru) |

Semua berada di jalur baru `docs/redesign/` — tidak ada file lama yang ditimpa.

## C. Backend (SQL lokal — BELUM diterapkan ke remote)

| Butir | Status | Catatan |
|---|---|---|
| `supabase_migrations/z214_discovery_geo.sql` | **PASS** (lokal) | Tabel `discovery_preferences` + `discovery_presence` (RLS deny-all), RPC `set_discovery_preference`, `upsert_discovery_presence` (anti-abuse 15 s, anti-teleport 350 m/s), `discover_nearby_users` (tanpa koordinat; jarak dibulatkan 10 m), `expire_my_presence`, `auto_cleanup_discovery_presence`; REVOKE eksplisit anon/PUBLIC |
| `supabase_migrations/z215_user_entitlements.sql` | **PASS** (lokal) | `user_entitlements` (RLS tanpa kebijakan DML), RPC `get_my_entitlements` (tidak pernah mengekspos `purchase_token`), `has_bluetooth_premium` |
| Guard SQL statis | **PASS** | `test/sql_discovery_regression_test.dart` 13/13 |
| **Penerapan ke Supabase remote** | **BLOCKED** | Memerlukan otorisasi & eksekusi owner. Selama belum diterapkan, `EntitlementService` memakai jembatan transisi `users.is_premium` (server-side, bukan flag lokal) |

## D. Implementasi Klien — Descubrimiento GPS+Red (Gratis)

| Butir | Status | Bukti |
|---|---|---|
| `lib/config/discovery_config.dart` | **PASS** | Radius {250, 500, 1000, 2000} m, default 500; validitas fix (akurasi ≤ 150 m, usia ≤ 2 mnt) |
| `lib/services/location_engine.dart` | **PASS** | `PositionSource`/`PermissionChecker` inyectable (geolocator 14.0.2), error tipado, pesan tanpa koordinat |
| `lib/services/internet_discovery_provider.dart` | **PASS** | Ditulis ulang bersih; RPC `discover_nearby_users`/preferences; sesi inyectable; clamp radius lokal |
| `lib/services/discovery_coordinator.dart` | **PASS** | Mesin status `idle/acquiringFix/live/hidden/offline/permissionBlocked/serverError/requiresAuth`; tanpa fallback otomatis GPS↔BT; tick manual-testable |
| UI radar (pemilih GPS/BT, chip radius, banner status) | **PASS** | `lib/screens/radar_screen.dart` |
| UI pengaturan (visibilitas, consent, radius) | **PASS** | `lib/screens/settings_screen.dart` |
| Test L-01…L-07 + mesin status koordinator | **PASS** | `test/discovery_engine_test.dart` (10), `test/discovery_coordinator_test.dart` (10) |
| **Validasi GPS di perangkat fisik** | **NOT VERIFIED** | Tidak ada perangkat terhubung (`adb devices` kosong) |

## E. Implementasi Klien — Premium (Radar Bluetooth)

| Butir | Status | Bukti |
|---|---|---|
| `lib/services/entitlement_service.dart` | **PASS** | Sumber kebenaran = backend (z215); status free/verifying/active/grace/canceledRenewal/expired/refundedRevoked/unknown; grace ≤ 24 h fail-closed; cache TTL 5 mnt + koalesensi; fallback transisi legacy server flag |
| `lib/services/play_billing_service.dart` | **PASS** | `in_app_purchase` 3.3.1; fail-closed: ack (`completePurchase`) **hanya setelah** verifikasi backend; tanpa harga inventado (produk dari `ProductDetails` Play); deep link kelola langganan |
| Gate BT di `NearbyService.startRadar()` | **PASS** | Revalidasi `loadForce()` → gagal `premiumRequired` sebelum menyentuh radio; test statis P-12 |
| `lib/screens/premium_screen.dart` | **PASS** | Billing Play nyata, status jujur, restore + kelola langganan; tidak me-dispose singleton billing |
| `donations_screen.dart` tanpa pembelian simulasi | **PASS** | `_buyPremium`/`setPremium(true)` dihapus |
| Flag lokal tidak bisa memberi akses (P-11) | **PASS** | `setPremium` hanya penanda inersia; gate membaca backend |
| Test P-01…P-12 | **PASS** | `test/entitlement_billing_test.dart` (18) |
| **Pembelian nyata di Play (produk, edge function `verify-play-purchase`, RTDN)** | **BLOCKED** | Produk & service account harus dibuat/deploy owner di Play Console + Supabase |

## F. Gerbang Verifikasi

| Gerbang | Status | Hasil |
|---|---|---|
| `flutter analyze --no-pub` | **PASS** | 0 masalah |
| `flutter test --no-pub` | **PASS** | **472/472** (434 baseline+SQL, +38 baru: engine 10, coordinator 10, entitlement/billing 18) |
| `git diff --check` | **PASS** | exit 0 (hanya peringatan CRLF normal Windows) |
| `flutter build apk --debug --dart-define-from-file=.env` | **PASS** | exit 0; run pertama menghasilkan APK lalu exception kosmetik Kotlin-incremental pada daemon; run kedua bersih |
| Artefak APK | **PASS** | `build/app/outputs/flutter-apk/app-debug.apk` — 208.960.343 byte (± 199,3 MiB); SHA-256 `6D0DB157A4CFE8532D700A1B459BB3A63DE76383BEC944B96DC8FAACAA6BA1AE` |
| Instalasi di perangkat fisik | **NOT RUN** | `adb devices` tanpa perangkat |

## G. Tindakan Owner yang Tersisa (di luar lingkup agent)

1. **Terapkan migrasi** `z214_discovery_geo.sql` + `z215_user_entitlements.sql` ke Supabase remote (dengan otorisasi owner). Setelah itu fallback legacy `users.is_premium` otomatis ditinggalkan.
2. **Play Console:** buat produk langganan `zone_premium_monthly` & `zone_premium_annual`, konfigurasikan akun layanan untuk verifikasi pembelian.
3. **Deploy edge function** `verify-play-purchase` di Supabase (kontrak: body `{productId, purchaseToken, packageName?}` → `{verified: true|false}`).
4. **Aktifkan RTDN** (real-time developer notifications) untuk pembaruan langganan (refund/cancel/expiry).
5. **Validasi di perangkat fisik:** fix GPS nyata, alur pembelian Play (test track), radar BT dengan dua perangkat.
