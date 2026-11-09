#!/usr/bin/env bash
# ==============================================================================
# setup_ubuntu.sh — Instalação completa do Vieira-STRIKE no Ubuntu 24.04
# Conforme Seções 1, 10, 11 e 12 da Auditoria Técnica (AUDITORIA_PROJETO.md)
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%T)]${NC} $*"; }
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $*"; }
err()  { echo -e "${RED}[ERRO]${NC} $*" >&2; }

if [ "$EUID" -ne 0 ]; then
    err "Este script deve ser executado com privilégios sudo: sudo bash setup_ubuntu.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

log "Iniciando configuração do servidor Vieira-STRIKE..."

# ── 1. Dependências do Sistema e 32-bit ────────────────────────────────────────
log "Instalando dependências de sistema e bibliotecas 32-bit para o HLDS..."
dpkg --add-architecture i386
apt-get update
apt-get install -y --no-install-recommends \
    curl unzip git lib32gcc-s1 lib32stdc++6 libpq5 \
    ca-certificates gnupg lsb-release

# Garante que o serviço do Docker esteja ativo
systemctl enable --now docker
info "Dependências instaladas e Docker ativo."

# ── 2. Usuário de Serviço Dedicado (cs16) ──────────────────────────────────────
if ! id -u cs16 >/dev/null 2>&1; then
    log "Criando usuário de serviço seguro 'cs16' sem login administrativo..."
    useradd -m -s /bin/bash cs16
    usermod -aG docker cs16
    info "Usuário 'cs16' criado."
else
    info "Usuário 'cs16' já existe."
    usermod -aG docker cs16 || true
fi

TARGET_DIR="/home/cs16/cs16-platform"
if [ "$REPO_DIR" != "$TARGET_DIR" ]; then
    log "Copiando repositório para o diretório padrão /home/cs16/cs16-platform..."
    mkdir -p "$TARGET_DIR"
    cp -r "$REPO_DIR/." "$TARGET_DIR/"
    chown -R cs16:cs16 "$TARGET_DIR"
fi

# ── 3. Preparação do .env e Certificados SSL ─────────────────────────────────
mkdir -p "$TARGET_DIR/infrastructure/nginx/ssl"
if [ ! -f "$TARGET_DIR/infrastructure/nginx/ssl/cert.pem" ]; then
    log "Gerando certificados SSL autoassinados para o Nginx..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$TARGET_DIR/infrastructure/nginx/ssl/key.pem" \
        -out "$TARGET_DIR/infrastructure/nginx/ssl/cert.pem" \
        -subj "/CN=vieira-strike" 2>/dev/null || true
    chown -R cs16:cs16 "$TARGET_DIR/infrastructure/nginx/ssl"
fi

if [ ! -f "$TARGET_DIR/.env" ]; then
    log "Criando arquivo .env a partir de .env.example com segredos aleatórios..."
    cp "$TARGET_DIR/.env.example" "$TARGET_DIR/.env"

    # Gerar senhas aleatórias seguras
    PG_PASS="$(openssl rand -hex 16)"
    SEC_KEY="$(openssl rand -hex 32)"
    WH_SEC="$(openssl rand -hex 24)"

    sed -i "s/defina_uma_senha_forte_para_admin_aqui/$PG_PASS/g" "$TARGET_DIR/.env"
    sed -i "s/defina_senha_backend/$PG_PASS/g" "$TARGET_DIR/.env"
    sed -i "s/gere_uma_chave_secreta_aleatoria_longa_e_segura/$SEC_KEY/g" "$TARGET_DIR/.env"
    sed -i "s/segredo_fornecido_pelo_gateway_de_pagamento/$WH_SEC/g" "$TARGET_DIR/.env"
    chown cs16:cs16 "$TARGET_DIR/.env"
    chmod 600 "$TARGET_DIR/.env"
    info ".env configurado com credenciais seguras."
fi

# Garante cópia do .env dentro de infrastructure para o Docker Compose
cp "$TARGET_DIR/.env" "$TARGET_DIR/infrastructure/.env"
chown cs16:cs16 "$TARGET_DIR/infrastructure/.env"
chmod 600 "$TARGET_DIR/infrastructure/.env"

# ── 4. Subida dos Containers (PostgreSQL, Backend FastAPI, Nginx FastDL) ──────
log "Subindo PostgreSQL, API Backend e Nginx via Docker Compose..."
cd "$TARGET_DIR/infrastructure"

# Limpa volumes e containers não saudáveis de tentativas anteriores
docker compose down -v 2>/dev/null || true
docker compose up -d

log "Aguardando PostgreSQL inicializar..."
for i in {1..30}; do
    if docker compose exec -T postgres pg_isready -U cs16_admin -d cs16 >/dev/null 2>&1; then
        info "PostgreSQL pronto para conexões."
        break
    fi
    sleep 2
done

# Extrai senha do postgres do .env
PG_PASS_VAL=$(grep '^POSTGRES_PASSWORD=' "$TARGET_DIR/.env" | cut -d '=' -f2)

# Cria usuário restrito do jogo no PostgreSQL e atualiza sql.cfg
log "Configurando permissões do usuário do jogo (cs16_game)..."
docker compose exec -T postgres psql -U cs16_admin -d cs16 -c "
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'cs16_game') THEN
            CREATE USER cs16_game WITH PASSWORD '$PG_PASS_VAL';
        ELSE
            ALTER USER cs16_game WITH PASSWORD '$PG_PASS_VAL';
        END IF;
    END
    \$\$;
" || true

# Configura sql.cfg com a senha gerada
SQL_CFG="$TARGET_DIR/game-server/cstrike/addons/amxmodx/configs/sql.cfg"
if [ -f "$SQL_CFG" ]; then
    sed -i "s/pass = .*/pass = \"$PG_PASS_VAL\"/g" "$SQL_CFG"
fi

# Aplicar schema inicial
log "Aplicando migração inicial 001_initial_schema.sql..."
docker compose exec -T postgres psql -U cs16_admin -d cs16 < "$TARGET_DIR/backend/migrations/001_initial_schema.sql" || true

# Concede permissões nas tabelas criadas ao usuário cs16_game
docker compose exec -T postgres psql -U cs16_admin -d cs16 -c "
    GRANT CONNECT ON DATABASE cs16 TO cs16_game;
    GRANT USAGE ON SCHEMA public TO cs16_game;
    GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO cs16_game;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cs16_game;
" || true

# Rodar seed inicial
log "Executando seed de catálogo e usuário Owner..."
sleep 2
docker compose exec -T backend python -m scripts.seed || warn "Seed já aplicado ou container inicializando."

# ── 5. Instalação do HLDS via SteamCMD ─────────────────────────────────────────
HLDS_DIR="/home/cs16/cs16-platform/game-server/hlds"
if [ ! -f "$HLDS_DIR/hlds_run" ]; then
    log "Instalando SteamCMD e HLDS legado (Counter-Strike 1.6)..."
    su - cs16 -c "
        mkdir -p ~/steamcmd
        cd ~/steamcmd
        if [ ! -f steamcmd.sh ]; then
            curl -sqL 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz' | tar zxvf -
        fi
        ./steamcmd.sh +force_install_dir '$HLDS_DIR' +login anonymous +app_set_config 90 mod cstrike +app_update 90 validate +quit || true
        # Rodada secundária do app_update necessária pelo GoldSrc
        ./steamcmd.sh +force_install_dir '$HLDS_DIR' +login anonymous +app_set_config 90 mod cstrike +app_update 90 validate +quit
    "
    info "HLDS baixado com sucesso."
else
    info "HLDS já instalado em $HLDS_DIR."
fi

# ── 6. Instalação de ReHLDS, ReGameDLL, AMX Mod X e ReAPI ─────────────────────
log "Instalando extensões ReHLDS, Metamod-R, ReGameDLL, AMXX e ReAPI..."
su - cs16 -c "bash $TARGET_DIR/infrastructure/install_extensions.sh"

log "Compilando plugins Pawn do Vieira-STRIKE..."
su - cs16 -c "bash $TARGET_DIR/infrastructure/install_plugins.sh"

# ── 7. Configuração do Serviço systemd ─────────────────────────────────────────
log "Configurando serviço do sistema (systemd/cs16.service)..."
cp "$TARGET_DIR/infrastructure/systemd/cs16.service" /etc/systemd/system/cs16.service
systemctl daemon-reload
systemctl enable --now cs16

info "=========================================================================="
info " Servidor Vieira-STRIKE configurado e em execução com sucesso!"
info "=========================================================================="
info " - Status do jogo:        systemctl status cs16"
info " - Logs do jogo:          journalctl -u cs16 -f"
info " - API e Containers:      cd $TARGET_DIR/infrastructure && docker compose ps"
info " - Conexão CS 1.6:        connect $(hostname -I | awk '{print $1}'):27015"
info "=========================================================================="
