#!/usr/bin/env bash
# ==============================================================================
# manage.sh — Utilitário de Gerenciamento do Servidor Vieira-STRIKE
# Uso:
#   ./manage.sh status     - Verifica status do jogo e containers
#   ./manage.sh logs       - Acompanha logs do jogo em tempo real
#   ./manage.sh restart    - Reinicia o servidor CS 1.6
#   ./manage.sh start      - Inicia todos os serviços
#   ./manage.sh stop       - Para todos os serviços
#   ./manage.sh backup     - Gera backup imediato do banco de dados
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

case "${1:-status}" in
    status)
        echo -e "${BLUE}=== Status dos Containers (Docker) ===${NC}"
        cd "$SCRIPT_DIR" && docker compose ps
        echo ""
        echo -e "${BLUE}=== Status do Servidor de Jogo (HLDS / systemd) ===${NC}"
        systemctl status cs16 --no-pager || true
        echo ""
        echo -e "${BLUE}=== Consumo de Memória do Sistema ===${NC}"
        free -h
        ;;
    logs)
        echo -e "${BLUE}Acompanhando logs do servidor Vieira-STRIKE (Ctrl+C para sair)...${NC}"
        journalctl -u cs16 -f
        ;;
    restart)
        echo -e "${YELLOW}Reiniciando servidor Vieira-STRIKE...${NC}"
        sudo systemctl restart cs16
        echo -e "${GREEN}Servidor reiniciado com sucesso!${NC}"
        ;;
    start)
        echo -e "${GREEN}Iniciando containers e servidor de jogo...${NC}"
        cd "$SCRIPT_DIR" && docker compose up -d
        sudo systemctl start cs16
        echo -e "${GREEN}Todos os serviços iniciados!${NC}"
        ;;
    stop)
        echo -e "${YELLOW}Parando servidor de jogo e containers...${NC}"
        sudo systemctl stop cs16 || true
        cd "$SCRIPT_DIR" && docker compose stop
        echo -e "${YELLOW}Todos os serviços foram parados.${NC}"
        ;;
    backup)
        echo -e "${BLUE}Gerando backup do banco de dados PostgreSQL...${NC}"
        BACKUP_FILE="$SCRIPT_DIR/backups/backup_$(date +%F_%H%M%S).sql.gz"
        mkdir -p "$SCRIPT_DIR/backups"
        cd "$SCRIPT_DIR"
        docker compose exec -T postgres pg_dump -U cs16_admin cs16 | gzip > "$BACKUP_FILE"
        echo -e "${GREEN}Backup concluído com sucesso: $BACKUP_FILE${NC}"
        ;;
    *)
        echo "Uso: $0 {status|logs|restart|start|stop|backup}"
        exit 1
        ;;
esac
