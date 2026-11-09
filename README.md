# Vieira-STRIKE — Plataforma Counter-Strike 1.6

Servidor customizado de Counter-Strike 1.6 com sistema de progressão por XP/níveis, inventário de skins/modelos, loja no jogo, backend FastAPI e integração com banco de dados PostgreSQL.

---

## 🚀 Arquitetura Geral

O ecossistema é dividido em duas frentes integradas:

1. **Servidor de Jogo (HLDS / ReHLDS)**
   - Motor ReHLDS com Metamod-R, ReGameDLL_CS, AMX Mod X 1.10 e ReAPI.
   - Executado via serviço `systemd` em Linux (Ubuntu) com usuário não-root.
   - Plugins AMXX (`.sma`) com consultas assíncronas (`SQL_ThreadQuery`) ao PostgreSQL.
   - Downloads rápidos de mapas e modelos via **Nginx FastDL**.

2. **Plataforma Web & API (FastAPI + PostgreSQL)**
   - API RESTful assíncrona documentada em OpenAPI (`/api/docs`).
   - Autenticação JWT com papéis RBAC (`owner`, `administrator`, `moderator`, `support`, `player`).
   - Gerenciamento de saldo, catálogo de itens, transações idempotentes e webhooks de pagamento.
   - Orquestrado via Docker Compose.

---

## 📂 Estrutura de Diretórios

```text
cs16-platform/
├── backend/                  # API FastAPI (autenticação, loja, carteira, admin)
│   ├── app/                  # Código-fonte da aplicação
│   ├── migrations/           # Schemas e migrações SQL (001_initial_schema.sql)
│   ├── requirements.txt      # Dependências Python
│   └── Dockerfile            # Container do backend
├── game-server/              # Configurações do HLDS / cstrike
│   └── cstrike/
│       ├── server.cfg        # Configurações do servidor (hostname: "Vieira-STRIKE")
│       └── addons/amxmodx/   # Plugins customizados Vieira-STRIKE
│           ├── configs/      # plugins.ini e sql.cfg
│           └── scripting/    # Códigos fonte Pawn (.sma)
├── infrastructure/           # Scripts de deploy e orquestração
│   ├── compose.yaml          # Orquestração Docker (Postgres, Backend, Nginx)
│   ├── install_extensions.sh # Instala ReHLDS, ReGameDLL, AMXX, ReAPI
│   ├── install_plugins.sh    # Compilador e instalador dos plugins Pawn
│   ├── nginx/                # Configurações de proxy reverso e FastDL
│   └── systemd/              # Serviço systemd cs16.service
├── fastdl-public/            # Diretório de arquivos públicos para download (maps/models)
├── .env.example              # Modelo de variáveis de ambiente
└── README.md
```

---

## 🛠️ Comandos dos Plugins no Jogo

- `/perfil` — Exibe seu nível atual, XP acumulado, patente e status da conta.
- `/inventario` — Lista os itens que você possui e quantos estão disponíveis.
- `/loja` — Abre o menu visual de compras para adquirir itens com saldo da conta.
- `/vincular CODIGO` — Vincula seu client ao painel web utilizando um código temporário de 8 dígitos.

---

## ⚡ Instalação Rápida

Consulte o arquivo [`AUDITORIA_PROJETO.md`](../AUDITORIA_PROJETO.md) para o plano de implantação detalhado e critérios de aceite de cada fase.
