# Arquitetura — Vieira-STRIKE

Este documento descreve a topologia, fluxo de dados e fronteiras de responsabilidade do servidor **Vieira-STRIKE**.

---

## 1. Visão Geral da Topologia

```text
                         Internet / LAN
                                |
                  +-------------+-------------+
                  |                           |
            Clientes CS                  Navegador web
                  |                           |
          UDP 27015 (jogo)                HTTPS 443
                  |                           |
  +---------------v---------------+   +-------v--------+
  | ReHLDS / CS 1.6               |   | Nginx          |
  | Metamod-R + AMX Mod X + ReAPI |   +-------+--------+
  | plugins Vieira-STRIKE         |           |
  +---------------+---------------+   +-------v--------+
                  |                   | FastAPI        |
                  | SQL privado       | painel + API   |
                  +---------+---------+-------+--------+
                            |                 |
                       +----v-----------------v----+
                       | PostgreSQL (rede privada) |
                       +---------------------------+

                 Nginx / FastDL -> apenas maps, models, sound
```

---

## 2. Princípios de Segurança e Isolamento

- **HLDS não roda como root:** Executado sob usuário de serviço sem privilégios via `systemd`.
- **Banco de Dados Privado:** O PostgreSQL nunca expõe portas diretamente para a internet. Fica restrito à rede interna do Docker / localhost.
- **Identidade Desacoplada (UUID):** SteamID e identificadores de clientes de terceiros não são chaves primárias. A conta interna utiliza UUIDv4 gerado pelo sistema.
- **Transações Atômicas:** Toda movimentação de saldo é gravada em `wallet_transactions` com chave de idempotência.
- **Consultas Assíncronas no Jogo:** Todas as chamadas SQL dentro do AMX Mod X utilizam obrigatoriamente `SQL_ThreadQuery` para não causar congelamento ou perda de ticks na rodada.
