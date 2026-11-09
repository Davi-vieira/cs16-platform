-- migrations/001_initial_schema.sql
-- Modelo de dados completo conforme seção 7 da auditoria.
-- Executar como usuário de migrations (não o usuário do jogo nem do backend).

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Jogadores ────────────────────────────────────────────────────────────────
CREATE TABLE players (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name VARCHAR(64)  NOT NULL,
    level        INT          NOT NULL DEFAULT 1 CHECK (level >= 1),
    xp           BIGINT       NOT NULL DEFAULT 0 CHECK (xp >= 0),
    rank         VARCHAR(32)  GENERATED ALWAYS AS (
        CASE
            WHEN level < 10 THEN 'Iniciante'
            WHEN level < 25 THEN 'Amador'
            WHEN level < 50 THEN 'Competente'
            WHEN level < 75 THEN 'Veterano'
            ELSE 'Elite'
        END
    ) STORED,
    status       VARCHAR(16)  NOT NULL DEFAULT 'visitor'
                              CHECK (status IN ('visitor','linked','verified','suspended')),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── Identidades externas ─────────────────────────────────────────────────────
CREATE TABLE player_identities (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id   UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    provider    VARCHAR(16) NOT NULL CHECK (provider IN ('steam','client','web')),
    external_id VARCHAR(64) NOT NULL,
    verified_at TIMESTAMPTZ,
    UNIQUE (provider, external_id)
);

CREATE INDEX ON player_identities (player_id);

-- ── Carteiras ────────────────────────────────────────────────────────────────
CREATE TABLE wallets (
    player_id  UUID        PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    balance    BIGINT      NOT NULL DEFAULT 0 CHECK (balance >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION trg_criar_carteira()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO wallets (player_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE TRIGGER after_player_insert
    AFTER INSERT ON players
    FOR EACH ROW EXECUTE FUNCTION trg_criar_carteira();

-- ── Transações de carteira ───────────────────────────────────────────────────
CREATE TABLE wallet_transactions (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id       UUID         NOT NULL REFERENCES players(id),
    type            VARCHAR(16)  NOT NULL CHECK (type IN ('topup','purchase','refund','adjustment')),
    amount          BIGINT       NOT NULL,
    currency        VARCHAR(3)   NOT NULL DEFAULT 'BRL',
    idempotency_key UUID         NOT NULL UNIQUE,
    reference_id    VARCHAR(128) UNIQUE,
    reason          TEXT,
    admin_id        UUID         REFERENCES players(id),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX ON wallet_transactions (player_id, created_at DESC);

-- ── Itens do catálogo ────────────────────────────────────────────────────────
CREATE TABLE items (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    sku           VARCHAR(64)  NOT NULL UNIQUE,
    display_name  VARCHAR(128) NOT NULL,
    item_type     VARCHAR(24)  NOT NULL CHECK (item_type IN ('weapon_skin','player_model')),
    price         BIGINT       NOT NULL CHECK (price >= 0),
    asset_version VARCHAR(32)  NOT NULL DEFAULT '1.0.0',
    enabled       BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── Inventário ───────────────────────────────────────────────────────────────
CREATE TABLE inventory_items (
    player_id               UUID    NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    item_id                 UUID    NOT NULL REFERENCES items(id),
    acquired_transaction_id UUID    REFERENCES wallet_transactions(id),
    equipped                BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (player_id, item_id)
);

CREATE INDEX ON inventory_items (player_id);

-- ── Pedidos de pagamento ─────────────────────────────────────────────────────
CREATE TABLE payment_orders (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id          UUID         NOT NULL REFERENCES players(id),
    provider           VARCHAR(32)  NOT NULL,
    provider_reference VARCHAR(128) UNIQUE,
    amount             BIGINT       NOT NULL CHECK (amount > 0),
    status             VARCHAR(16)  NOT NULL DEFAULT 'pending'
                                    CHECK (status IN ('pending','confirmed','failed','refunded')),
    webhook_payload    JSONB,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    confirmed_at       TIMESTAMPTZ
);

CREATE INDEX ON payment_orders (player_id, created_at DESC);
CREATE INDEX ON payment_orders (status) WHERE status = 'pending';

-- ── Papéis administrativos ───────────────────────────────────────────────────
CREATE TABLE admin_roles (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id  UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    role       VARCHAR(16) NOT NULL CHECK (role IN ('owner','administrator','moderator','support')),
    granted_by UUID        REFERENCES players(id),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,
    UNIQUE (player_id, role)
);

-- ── Log de auditoria ─────────────────────────────────────────────────────────
CREATE TABLE admin_audit_logs (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id    UUID        NOT NULL REFERENCES players(id),
    action      VARCHAR(64) NOT NULL,
    target_type VARCHAR(32),
    target_id   UUID,
    payload     JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ON admin_audit_logs (admin_id, created_at DESC);
CREATE INDEX ON admin_audit_logs (target_id) WHERE target_id IS NOT NULL;

-- ── Códigos de vinculação ────────────────────────────────────────────────────
CREATE TABLE link_codes (
    code       VARCHAR(8)  PRIMARY KEY,
    player_id  UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '15 minutes',
    used_at    TIMESTAMPTZ
);

CREATE INDEX ON link_codes (player_id);

-- ── Manifesto de assets ──────────────────────────────────────────────────────
CREATE TABLE asset_manifests (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    sku          VARCHAR(64)  NOT NULL REFERENCES items(sku),
    version      VARCHAR(32)  NOT NULL,
    file_path    VARCHAR(256) NOT NULL,
    sha256       CHAR(64)     NOT NULL,
    file_size    BIGINT       NOT NULL,
    published_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (sku, version)
);

COMMIT;
