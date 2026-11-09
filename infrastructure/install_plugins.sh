#!/usr/bin/env bash
# install_plugins.sh
# Compila e instala os plugins AMXX da plataforma cs16
# Requer: amxxpc (compilador AMXX) disponível no PATH ou em AMXX_DIR
set -euo pipefail

HLDS_DIR="${HLDS_DIR:-$HOME/cs16-platform/game-server/hlds}"
CS_DIR="$HLDS_DIR/cstrike"
AMXX_DIR="$CS_DIR/addons/amxmodx"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTING="$REPO_DIR/game-server/cstrike/addons/amxmodx/scripting"
COMPILER="$AMXX_DIR/scripting/amxxpc"

log() { echo "[$(date +%H:%M:%S)] $*"; }

if [ ! -f "$COMPILER" ]; then
    log "ERRO: compilador amxxpc não encontrado em $COMPILER"
    log "Instale o AMX Mod X antes de rodar este script."
    exit 1
fi

PLUGINS=(
    cs16_perfil
    cs16_xp
    cs16_inventario
    cs16_loja
    cs16_vincular
)

for plugin in "${PLUGINS[@]}"; do
    SRC="$SCRIPTING/${plugin}.sma"
    if [ ! -f "$SRC" ]; then
        log "AVISO: $SRC não encontrado, pulando."
        continue
    fi
    log "Compilando $plugin..."
    "$COMPILER" "$SRC" -o "$AMXX_DIR/plugins/${plugin}.amxx" \
        -i "$AMXX_DIR/scripting/include"
    log "$plugin compilado e instalado."
done

log "Todos os plugins instalados. Reinicie o servidor para carregar."
