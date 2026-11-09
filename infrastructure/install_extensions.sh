#!/usr/bin/env bash
# install_extensions.sh
# Instala ReHLDS, Metamod-R, ReGameDLL_CS, AMX Mod X 1.10 e ReAPI
# Executar como usuário de serviço (não root), após HLDS legado instalado via SteamCMD
set -euo pipefail

HLDS_DIR="${HLDS_DIR:-$HOME/cs16-platform/game-server/hlds}"
CS_DIR="$HLDS_DIR/cstrike"
ADDONS="$CS_DIR/addons"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REHLDS_VER="3.13.0.788"
METAMOD_VER="1.3.0.149"
REGAMEDLL_VER="5.26.0.668"
AMXX_VER="1.10.0"
REAPI_VER="5.24.0.300"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# ── ReHLDS ───────────────────────────────────────────────────────────────────
log "Baixando ReHLDS $REHLDS_VER..."
curl -fsSL "https://github.com/rehlds/ReHLDS/releases/download/${REHLDS_VER}/rehlds-bin-${REHLDS_VER}.zip" \
    -o "$TMP/rehlds.zip"
unzip -q "$TMP/rehlds.zip" -d "$TMP/rehlds"
cp "$TMP/rehlds/bin/linux32/engine_i486.so"    "$HLDS_DIR/"
cp "$TMP/rehlds/bin/linux32/filesystem_stdio.so" "$HLDS_DIR/"
log "ReHLDS instalado."

# ── Metamod-R ────────────────────────────────────────────────────────────────
log "Baixando Metamod-R $METAMOD_VER..."
curl -fsSL "https://github.com/rehlds/Metamod-R/releases/download/${METAMOD_VER}/metamod-bin-${METAMOD_VER}.zip" \
    -o "$TMP/metamod.zip"
unzip -q "$TMP/metamod.zip" -d "$TMP/metamod"
mkdir -p "$ADDONS/metamod/dlls"
cp "$TMP/metamod/addons/metamod/dlls/metamod.so" "$ADDONS/metamod/dlls/"

LIBLIST="$CS_DIR/liblist.gam"
if grep -q "gamedll_linux" "$LIBLIST"; then
    sed -i 's|gamedll_linux.*|gamedll_linux "addons/metamod/dlls/metamod.so"|' "$LIBLIST"
else
    echo 'gamedll_linux "addons/metamod/dlls/metamod.so"' >> "$LIBLIST"
fi
log "Metamod-R instalado."

# ── ReGameDLL_CS ─────────────────────────────────────────────────────────────
log "Baixando ReGameDLL_CS $REGAMEDLL_VER..."
curl -fsSL "https://github.com/rehlds/ReGameDLL_CS/releases/download/${REGAMEDLL_VER}/regamedll-bin-${REGAMEDLL_VER}.zip" \
    -o "$TMP/regamedll.zip"
unzip -q "$TMP/regamedll.zip" -d "$TMP/regamedll"
mkdir -p "$ADDONS/regamedll/dlls"
cp "$TMP/regamedll/cstrike/addons/regamedll/dlls/cs.so" "$ADDONS/regamedll/dlls/"

PLUGINS_INI="$ADDONS/metamod/plugins.ini"
grep -qF "regamedll" "$PLUGINS_INI" 2>/dev/null || \
    echo 'linux addons/regamedll/dlls/cs.so' >> "$PLUGINS_INI"
log "ReGameDLL_CS instalado."

# ── AMX Mod X 1.10 ───────────────────────────────────────────────────────────
log "Baixando AMX Mod X $AMXX_VER..."
AMXX_BASE="https://www.amxmodx.org/release"
curl -fsSL "${AMXX_BASE}/amxmodx-${AMXX_VER}-base-linux.tar.gz"    -o "$TMP/amxx_base.tar.gz"
curl -fsSL "${AMXX_BASE}/amxmodx-${AMXX_VER}-cstrike-linux.tar.gz" -o "$TMP/amxx_cs.tar.gz"
tar -xzf "$TMP/amxx_base.tar.gz" -C "$CS_DIR"
tar -xzf "$TMP/amxx_cs.tar.gz"   -C "$CS_DIR"

grep -qF "amxmodx" "$PLUGINS_INI" 2>/dev/null || \
    echo 'linux addons/amxmodx/dlls/amxmodx_mm_i386.so' >> "$PLUGINS_INI"
log "AMX Mod X instalado."

# ── ReAPI ─────────────────────────────────────────────────────────────────────
log "Baixando ReAPI $REAPI_VER..."
curl -fsSL "https://github.com/rehlds/ReAPI/releases/download/${REAPI_VER}/reapi-bin-${REAPI_VER}.zip" \
    -o "$TMP/reapi.zip"
unzip -q "$TMP/reapi.zip" -d "$TMP/reapi"
mkdir -p "$ADDONS/reapi/dlls"
cp "$TMP/reapi/addons/reapi/dlls/reapi_amxx_i386.so" "$ADDONS/reapi/dlls/"

grep -qF "reapi" "$PLUGINS_INI" 2>/dev/null || \
    echo 'linux addons/reapi/dlls/reapi_amxx_i386.so' >> "$PLUGINS_INI"
log "ReAPI instalado."

# ── Copiar configs e plugins ──────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
log "Copiando configs e plugins do repositório..."
cp -r "$REPO_DIR/game-server/cstrike/." "$CS_DIR/"
chmod +x "$HLDS_DIR/hlds_run" "$HLDS_DIR/hlds_linux" 2>/dev/null || true
log "Configs copiados."

log "Todas as extensões instaladas. Próximo passo: bash install_plugins.sh"
