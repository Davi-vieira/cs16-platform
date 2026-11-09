# Runbook de Operação — Vieira-STRIKE

Guia prático para instalação, inicialização, monitoramento e manutenção do servidor **Vieira-STRIKE**.

---

## 1. Pré-Requisitos no Servidor (Ubuntu)

```bash
# 1. Dependências do sistema e bibliotecas 32-bit para o HLDS
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y lib32gcc-s1 lib32stdc++6 curl unzip git libpq5

# 2. Usuário de serviço dedicado (sem privilégios administrativos)
sudo useradd -m -s /bin/bash cs16
```

---

## 2. Inicialização dos Containers (Backend + Banco + Nginx)

```bash
cd /home/cs16/cs16-platform/infrastructure
cp ../.env.example .env
# Edite o .env com senhas fortes
nano .env

# Sobe PostgreSQL, API FastAPI e Nginx
docker compose up -d
```

---

## 3. Instalação e Inicialização do Servidor de Jogo

```bash
# Executado como usuário cs16:
cd /home/cs16/cs16-platform/infrastructure
bash install_extensions.sh
bash install_plugins.sh

# Configuração e inicialização do serviço systemd
sudo cp systemd/cs16.service /etc/systemd/system/cs16.service
sudo systemctl daemon-reload
sudo systemctl enable cs16
sudo systemctl start cs16
```

---

## 4. Monitoramento e Logs

```bash
# Status do servidor CS 1.6
systemctl status cs16

# Logs em tempo real do jogo
journalctl -u cs16 -f

# Logs da infraestrutura Docker
docker compose logs -f backend
docker compose logs -f postgres
```

---

## 5. Rotina de Backup do Banco de Dados

```bash
docker exec -t infrastructure-postgres-1 pg_dump -U cs16_admin cs16 | gzip > /home/cs16/backups/cs16_$(date +%F_%H%M%S).sql.gz
```
