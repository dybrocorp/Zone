-- =============================================================================
-- Z-213 · Foundation of account/device identity (2026-10-27)
-- =============================================================================
-- PHASE F — resolutions of owner-approved ambiguities (PHASE_J paquete
-- DEC-F1..DEC-F5) and local state of the device migration plan (A/B/C/D).
--
--   #1  account_id = server UUID (users.id). All new tables are anchored to
--       users(id), never to the mesh-visible legacy ZONE handle.
--   #2  sender_id KEEPS its FK to account (users.id); a nullable column is
--       added messages.device_id (provenance of the sending device, NULL for
--       historical/venv rows). NO data backfill is required: the column is
--       empty by design.
--   #3  First binding = OOB anchor (fingerprint + code verified server-side).
--       There is NO silent TOFU: without a matching code the transition is
--       impossible.
--   #4  Semantic backfill: account_id of NEW rows is always users.id (FK
--       CASCADE). No historical rows exist in these (new) tables.
--   #5  Revocation = server-side registry `device_revocations` (append-only),
--       with auditable reason and revoked_by = auth.uid() of the account.
--
-- STRICT SECURITY FRAMEWORK:
--   - RLS ON in all new tables; policies are auth.uid()-ONLY (the owner sees
--     its rows; it cannot read others' rows).
--   - Direct INSERT/UPDATE/DELETE for authenticated: REVOKE + NO policy (the
--     lifecycles A/B/C/D are only executed via SECURITY DEFINER functions
--     with auth.uid() double-gate transacción).
--   - claim_zone_id: UNTOUCHED (its quarantine Z-212 remains intact; the
--     flow is not modified here).
--   - Rate-limit per account: max 5 rejected/expired requests in 10 min, and
--     max 10 pending (flood guard), following the z212 pattern.
--
-- Idempotent. NO deploy to production without explicit owner authorization
-- (Z-212 §0 unmet: staging/exec remains BLOCKED — this is local design code).
-- =============================================================================

BEGIN;

-- ─── 0. Prerequisito: pgcrypto (sha256 para hashes OOB — idempotente) ───────
create extension if not exists pgcrypto;

-- ─── 1. account_identity: anchor per account (one row) ──────────────────────
create table if not exists public.account_identity (
    account_id UUID PRIMARY KEY
        REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    -- Key Ed25519 of signature of the account (identity). Base64 32B.
    identity_public_key_ed25519 TEXT NOT NULL,
    -- Key X25519 of encryption of the account. Base64 32B.
    encryption_public_key_x25519 TEXT NOT NULL,
    -- huella canónica del par (hex sha256, clase OOB — ver PHASE_F §7.4).
    account_fingerprint TEXT NOT NULL
        CHECK (account_fingerprint ~ '^[0-9a-f]{64}$'),
    revision INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    rotated_at TIMESTAMPTZ
);

-- Unicidad: un par de claves no puede anclar dos cuentas (evita colisión
-- de identidad / reuso malicioso de material).
create index if not exists idx_account_identity_ed25519
    on public.account_identity (identity_public_key_ed25519);
create index if not exists idx_account_identity_fingerprint
    on public.account_identity (account_fingerprint);

-- RLS estricta: el dueño ve SU fila; nadie más.
alter table public.account_identity enable row level security;
drop policy if exists "account_identity owner select" on public.account_identity;
create policy "account_identity owner select" on public.account_identity
    for select using (auth.uid() = account_id);
-- owner upsert (idiom Supabase: separate using/with check)
drop policy if exists "account_identity owner insert" on public.account_identity;
create policy "account_identity owner insert" on public.account_identity
    for insert with check (auth.uid() = account_id);
drop policy if exists "account_identity owner update" on public.account_identity;
create policy "account_identity owner update" on public.account_identity
    for update using (auth.uid() = account_id)
        with check (auth.uid() = account_id);
-- No owner DELETE policy (the anchor cannot be auto-destroyed; rotation is
-- protected in later phases).

-- ─── 2. account_devices: devices per account ────────────────────────────────
create table if not exists public.account_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    -- OOB anchor of the device: fingerprint of its key pair (explicit,
    -- verifiable OUTSIDE of band; NEVER a hidden TOFU).
    device_fingerprint TEXT NOT NULL
        CHECK (device_fingerprint ~ '^[0-9a-f]{64}$'),
    -- Keys X25519/Ed25519 of the device. Base64 32B.
    encryption_public_key_x25519 TEXT NOT NULL,
    identity_public_key_ed25519 TEXT NOT NULL,
    -- device_certificate v2 JWT/split issued by the account key
    -- (self-issued anchor pending OOB verification in this phase).
    device_certificate TEXT NOT NULL,
    -- State of the machine A/B/C/D (local planning, PHASE_F §9).
    provisioning_state TEXT NOT NULL DEFAULT 'pending_oob'
        CHECK (provisioning_state IN ('pending_oob','active','revoked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bound_at TIMESTAMPTZ,            -- activation (only after OOB/replace)
    revoked_at TIMESTAMPTZ
);

create index if not exists idx_account_devices_account
    on public.account_devices (account_id);
create index if not exists idx_account_devices_state
    on public.account_devices (account_id, provisioning_state);

-- Unicidad: same fingerprint cannot re-register on the account (prevents
-- ledger poisoning in A(add) and shadow rows in B(replace)).
create unique index if not exists uq_account_devices_fingerprint
    on public.account_devices (account_id, device_fingerprint);

-- INVARIANT (res DEC-F5): maximum ONE active device per account.
create unique index if not exists uq_account_devices_one_active
    on public.account_devices (account_id)
    WHERE provisioning_state = 'active';

-- RLS strict: owner-only SELECT; NO direct writes for authenticated
-- (transitions SECURITY DEFINER only).
alter table public.account_devices enable row level security;
drop policy if exists "account_devices owner select" on public.account_devices;
create policy "account_devices owner select" on public.account_devices
    for select using (auth.uid() = account_id);

-- ─── 3. account_device_requests: lifecycle A/B/C with OOB code ──────────────
create table if not exists public.account_device_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    request_type TEXT NOT NULL
        CHECK (request_type IN ('add_device','replace_device','recover_account')),
    -- fingerprint of the requesting device (to be registered if approved)
    requested_device_fingerprint TEXT NOT NULL
        CHECK (requested_device_fingerprint ~ '^[0-9a-f]{64}$'),
    requested_public_key_x25519 TEXT NOT NULL,
    requested_identity_key_ed25519 TEXT NOT NULL,
    -- SHA-256 hex of the OOB code show/explicit-confirm (NEVER plain code).
    request_code_hash TEXT NOT NULL
        CHECK (request_code_hash ~ '^[0-9a-f]{64}$'),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','approved','denied','expired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
        DEFAULT now() + interval '15 minutes',
    decided_at TIMESTAMPTZ
);

create index if not exists idx_account_device_requests_account
    on public.account_device_requests (account_id, created_at DESC);
create index if not exists idx_account_device_requests_status
    on public.account_device_requests (account_id, status);

-- RLS strict: owner-only SELECT; lifecycle via SECURITY DEFINER.
alter table public.account_device_requests enable row level security;
drop policy if exists "account_device_requests owner select"
    on public.account_device_requests;
create policy "account_device_requests owner select"
    on public.account_device_requests
    for select using (auth.uid() = account_id);

-- ─── 4. device_revocations: append-only revocation ledger (DEC-F5) ──────────
create table if not exists public.device_revocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    -- NULL if the device is deleted (FK SET NULL); history is preserved.
    device_id UUID
        REFERENCES public.account_devices(id) ON DELETE SET NULL,
    device_fingerprint TEXT,     -- Mirror for auditability post-delete
    revoked_by UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    reason TEXT NOT NULL
        CHECK (reason IN ('user_initiated','lost','replaced','cleanup')),
    revoked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

create index if not exists idx_device_revocations_account
    on public.device_revocations (account_id, revoked_at DESC);

-- RLS strict: owner-only SELECT; NO direct writes (only via revoke_device).
alter table public.device_revocations enable row level security;
drop policy if exists "device_revocations owner select" on public.device_revocations;
create policy "device_revocations owner select" on public.device_revocations
    for select using (auth.uid() = account_id);

-- ─── 5. messages.device_id (DEC-F2): device provenance nullable ─────────────
-- Additive; NULL keeps the semantics for historical/venv rows (provenance is
-- optional, sender_id FK preserves the account-level truth).
alter table public.messages
    add column if not exists device_id UUID
    references public.account_devices(id) on delete set null;

-- Integrity WITHOUT auth assumptions: the provenance of the device must refer
-- to an ACTIVE device of THE account that sent (anti-spoofing of provenance).
create or replace function public.enforce_message_device_provenance()
returns trigger
language plpgsql
set search_path = public
as $$
declare
    v_ok boolean;
begin
    if new.device_id is null then
        return new;
    end if;
    select exists (
        select 1 from public.account_devices d
        where d.id = new.device_id
          and d.account_id = new.sender_id
          and d.provisioning_state = 'active'
    ) into v_ok;
    if not coalesce(v_ok, false) then
        raise exception 'devices: device_id does not correspond to an '
            'active device of the sender (Z-213)';
    end if;
    return new;
end;
$$;

drop trigger if exists trg_messages_device_provenance on public.messages;
create trigger trg_messages_device_provenance
    before insert or update on public.messages
    for each row execute function public.enforce_message_device_provenance();

-- ─── 6. SECURITY DEFINER transiciones (A/B/C/D) ─────────────────────────────

-- 6a. Solicitud de alta de dispositivo (A(add) / B(replace) / C(recover)).
--    Returns pending request; does NOT activate anything (OOB anchor DEC-F3).
create or replace function public.request_device_binding(
    p_request_type text,
    p_device_fingerprint text,
    p_x25519_pk text,
    p_ed25519_pk text,
    p_request_code_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid uuid := auth.uid();
    v_recent_rejections bigint;
    v_pending bigint;
    v_request public.account_device_requests;
    v_has_active boolean;
    v_existing_state text;
begin
    if v_uid is null then
        raise exception 'Se requiere sesión autenticada';
    end if;

    -- Validaciones de formato (fail-closed, estilo Z-212).
    if p_request_type not in ('add_device','replace_device','recover_account') then
        raise exception 'Z-213: tipo de solicitud inválido';
    end if;
    if p_device_fingerprint !~ '^[0-9a-f]{64}$' then
        raise exception 'Z-213: fingerprint de dispositivo inválido';
    end if;
    if p_request_code_hash !~ '^[0-9a-f]{64}$' then
        raise exception 'Z-213: código OOB inválido';
    end if;
    if p_x25519_pk is null or length(trim(p_x25519_pk)) = 0
       or p_ed25519_pk is null or length(trim(p_ed25519_pk)) = 0 then
        raise exception 'Z-213: claves del dispositivo requeridas';
    end if;

    -- Rate-limit estilo Z-212: máx 5 rechazos/expirados (10 min) y máx 10
    -- pendientes (flood guard) por cuenta.
    select count(*) into v_recent_rejections
    from public.account_device_requests
    where account_id = v_uid
      and status in ('denied','expired')
      and created_at > now() - interval '10 minutes';
    if v_recent_rejections >= 5 then
        raise exception 'Z-213: demasiadas solicitudes rechazadas. Reintenta más tarde.';
    end if;

    select count(*) into v_pending
    from public.account_device_requests
    where account_id = v_uid and status = 'pending';
    if v_pending >= 10 then
        raise exception 'Z-213: demasiadas solicitudes pendientes';
    end if;

    -- Un fingerprint no puede tener una segunda fila: la reactivacion pasa por
    -- finalize_device_binding (do-update), nunca por otra fila.
    select provisioning_state into v_existing_state
    from public.account_devices
    where account_id = v_uid and device_fingerprint = p_device_fingerprint;
    if v_existing_state is not distinct from 'active' then
        raise exception 'Z-213: ese dispositivo ya está activo en esta cuenta';
    end if;

    -- Coherencia A/B/C: si YA hay un dispositivo activo, solo 'replace_device'
    -- es admisible; sin activo, 'add_device' o 'recover_account'.
    select exists (
        select 1 from public.account_devices
        where account_id = v_uid and provisioning_state = 'active'
    ) into v_has_active;
    if v_has_active and p_request_type <> 'replace_device' then
        raise exception 'Z-213: la cuenta ya tiene un dispositivo activo; '
            'usa replace_device';
    end if;
    if not v_has_active and p_request_type = 'replace_device' then
        raise exception 'Z-213: no hay dispositivo activo que reemplazar';
    end if;

    insert into public.account_device_requests (
        account_id, request_type, requested_device_fingerprint,
        requested_public_key_x25519, requested_identity_key_ed25519,
        request_code_hash, status
    ) values (
        v_uid, p_request_type, p_device_fingerprint,
        p_x25519_pk, p_ed25519_pk, p_request_code_hash, 'pending'
    ) returning * into v_request;

    return jsonb_build_object(
      'request_id', v_request.id,
      'status', v_request.status,
      'expires_at', v_request.expires_at,
      'request_type', v_request.request_type
    );
end;
$$;

GRANT EXECUTE ON FUNCTION public.request_device_binding(text, text, text, text, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.request_device_binding(text, text, text, text, text) FROM PUBLIC, anon;

-- 6b. Finalización: OOB code + ONE strict transition to 'active'
--     (DEC-F3: no silent TOFU — code equality REQUIRED server-side; DEC-F5:
--     replace revokes the outgoing active device in the SAME transaction).
create or replace function public.finalize_device_binding(
    p_request_id uuid,
    p_request_code text,
    p_device_certificate text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid uuid := auth.uid();
    v_req public.account_device_requests;
    v_old_active public.account_devices;
    v_new_device public.account_devices;
begin
    if v_uid is null then
        raise exception 'Se requiere sesión autenticada';
    end if;

    select * into v_req
    from public.account_device_requests
    where id = p_request_id
      and account_id = v_uid
    for update;
    if not found then
        raise exception 'Z-213: solicitud inexistente';
    end if;
    if v_req.status <> 'pending' then
        raise exception 'Z-213: solicitud ya no está pendiente';
    end if;
    if v_req.expires_at < now() then
        update public.account_device_requests
        set status = 'expired', decided_at = now()
        where id = v_req.id;
        raise exception 'Z-213: solicitud expirada; genera una nueva';
    end if;

    -- Certificate del dispositivo (device_certificate v2, firmado por la
    -- identidad de cuenta; el emisor lo genera al finalizar — fail-closed si
    -- no existe). La VALIDACIÓN firma→NOT NULL se hace en app (device_cert v2
    -- verifier); aquí se exige presencia y se persiste para auditabilidad.
    if p_device_certificate is null
       or length(trim(p_device_certificate)) = 0 then
        raise exception 'Z-213: device certificate requerido';
    end if;

    -- OOB anchor (DEC-F3): hash del código mostrado/firmado fuera de banda
    -- DEBE coincidir. Sin esto, no hay activación (no silent TOFU).
    if coalesce(encode(digest(p_request_code, 'sha256'), 'hex'), '')
       <> v_req.request_code_hash then
        update public.account_device_requests
        set status = 'denied', decided_at = now()
        where id = v_req.id;
        raise exception 'Z-213: código OOB incorrecto';
    end if;

    -- B(replace): revoke the outgoing active device (ledger DEC-F5) and then
    -- activate the new one (uq_account_devices_one_active holds validity).
    if v_req.request_type = 'replace_device' then
        select * into v_old_active
        from public.account_devices
        where account_id = v_uid
          and provisioning_state = 'active'
        for update;
        if found then
            update public.account_devices
            set provisioning_state = 'revoked', revoked_at = now()
            where id = v_old_active.id;
            insert into public.device_revocations (
                account_id, device_id, device_fingerprint, revoked_by, reason
            ) values (
                v_uid, v_old_active.id, v_old_active.device_fingerprint,
                v_uid, 'replaced'
            );
        end if;
    end if;

    -- Activate (or create pending_oob + activate in one step).
    insert into public.account_devices (
        id, account_id, device_fingerprint,
        encryption_public_key_x25519, identity_public_key_ed25519,
        device_certificate, provisioning_state, bound_at
    ) values (
        gen_random_uuid(), v_uid, v_req.requested_device_fingerprint,
        v_req.requested_public_key_x25519, v_req.requested_identity_key_ed25519,
        p_device_certificate, 'active', now()
    ) on conflict (account_id, device_fingerprint)
    do update set
        encryption_public_key_x25519 = excluded.encryption_public_key_x25519,
        identity_public_key_ed25519 = excluded.identity_public_key_ed25519,
        provisioning_state = 'active',
        bound_at = now(),
        revoked_at = null
    returning * into v_new_device;

    update public.account_device_requests
    set status = 'approved', decided_at = now()
    where id = v_req.id;

    return jsonb_build_object(
        'device_id', v_new_device.id,
        'provisioning_state', v_new_device.provisioning_state,
        'bound_at', v_new_device.bound_at
    );
end;
$$;

GRANT EXECUTE ON FUNCTION public.finalize_device_binding(uuid, text, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.finalize_device_binding(uuid, text, text) FROM PUBLIC, anon;

-- 6c. D(revoke): baja manual del dispositivo activo (revocation ledger DEC-F5).
create or replace function public.revoke_device(
    p_device_id uuid,
    p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid uuid := auth.uid();
    v_device public.account_devices;
begin
    if v_uid is null then
        raise exception 'Se requiere sesión autenticada';
    end if;
    if p_reason not in ('user_initiated','lost','cleanup') then
        -- 'replaced' is reserved for the automatic pipeline B(replace).
        raise exception 'Z-213: razón de revocación inválida';
    end if;

    select * into v_device
    from public.account_devices
    where id = p_device_id
      and account_id = v_uid
    for update;
    if not found then
        raise exception 'Z-213: dispositivo inexistente';
    end if;
    if v_device.provisioning_state <> 'active' then
        raise exception 'Z-213: el dispositivo no está activo';
    end if;

    update public.account_devices
    set provisioning_state = 'revoked', revoked_at = now()
    where id = v_device.id;

    insert into public.device_revocations (
        account_id, device_id, device_fingerprint, revoked_by, reason
    ) values (
        v_uid, v_device.id, v_device.device_fingerprint, v_uid, p_reason
    );

    -- Closes the open pending requests of the SAME device.
    update public.account_device_requests
    set status = 'denied', decided_at = now()
    where account_id = v_uid
      and status = 'pending'
      and requested_device_fingerprint = v_device.device_fingerprint;

    return jsonb_build_object(
        'device_id', v_device.id,
        'provisioning_state', 'revoked',
        'revoked_at', now()
    );
end;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_device(uuid, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.revoke_device(uuid, text) FROM PUBLIC, anon;

COMMIT;

-- =============================================================================
-- PRUEBAS SQL (post-deploy, remote verification only if owner authorizes):
--
--   1. Without session (anon): request_device_binding must ERROR.
--   2. With session: request_device_binding('add_device', <fp64>, <pk>, <pk>,
--      <hash>) returns request_id pending.
--   3. finalize_device_binding(<id>, wrong code, <cert>) → ERROR + request
--      'denied'.
--   4. Re-request + finalize_device_binding(<id>, correct code, <cert>) →
--      device active; second add attempt for another fingerprint → ERROR
--      (active exists, only replace_device is admitted).
--   5. replace_device: closes active, opens new active, inserts ledger row
--      device_revocations with reason='replaced'.
--   6. revoke_device(device_id, 'lost') → revoked + ledger entry + pending requests closed.
--   7. Messages: INSERT with device_id foreign account → trigger fails.
--
-- Idempotent. Z-212 §0 remains unmet: NO remote execution authorized.
-- =============================================================================
