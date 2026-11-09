# Especificação da API — Vieira-STRIKE

A API RESTful do servidor Vieira-STRIKE é construída em FastAPI e documentada interativamente via OpenAPI em `/api/docs`.

---

## 1. Autenticação (`/api/auth`)

- `POST /api/auth/login`: Realiza login com credenciais e retorna um token Bearer JWT (`access_token`).

---

## 2. Jogadores (`/api/players`)

- `GET /api/players/me`: Retorna os dados do perfil autenticado (nível, XP, rank, status).
- `GET /api/players/{player_id}`: Retorna dados públicos de um jogador por UUID.
- `POST /api/players/me/link-code`: Gera um código temporário de 8 dígitos para vincular a conta dentro do jogo com `/vincular <CODIGO>`.

---

## 3. Catálogo de Itens (`/api/items`)

- `GET /api/items/`: Lista itens ativos e seus preços em centavos (BRL).
- `POST /api/items/`: Cadastra novo item no catálogo (requer papel `administrator`).
- `PATCH /api/items/{item_id}/toggle`: Habilita ou desabilita um item da loja.

---

## 4. Carteira e Saldo (`/api/wallet`)

- `GET /api/wallet/me`: Consulta o saldo atual da carteira em centavos.
- `GET /api/wallet/me/transactions`: Lista as últimas 50 transações da conta.
- `POST /api/wallet/adjust`: Ajuste manual de saldo (exige `administrator` e motivo auditado).

---

## 5. Pagamentos e Webhooks (`/api/payments`, `/api/webhooks`)

- `POST /api/payments/order`: Cria um novo pedido de recarga (ex.: PIX).
- `POST /api/webhooks/payment`: Endpoint chamado pelo gateway de pagamento para confirmação assíncrona com validação de assinatura e chave de idempotência.

---

## 6. Administração (`/api/admin`)

- `GET /api/admin/stats`: Métricas gerais da plataforma (jogadores, itens, faturamento).
- `GET /api/admin/audit-logs`: Trilha de auditoria das ações administrativas.
- `POST /api/admin/roles/grant`: Concede papel RBAC a um usuário (requer `owner`).
- `POST /api/admin/roles/revoke`: Revoga papel RBAC de um usuário (requer `owner`).
- `PATCH /api/admin/players/{player_id}/status`: Altera status de uma conta (ex.: `suspended`).
