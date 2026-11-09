# Auditoria técnica — Servidor Counter-Strike 1.6 com progressão e loja

**Status:** aprovado com ressalvas  
**Data:** 09/11/2026  
**Escopo:** servidor CS 1.6 no Ubuntu, conteúdo customizado, níveis, inventário, loja no jogo, painel administrativo e recargas.

## 1. Decisão executiva

O projeto é viável, desde que seja tratado como dois sistemas conectados:

1. **Servidor de jogo:** responsável pela partida, menu, aplicação visual de itens e telemetria de gameplay.
2. **Plataforma web:** responsável por contas, catálogo, permissões, saldo, pagamentos, auditoria e administração.

O servidor deve partir de **HLDS legado oficial instalado por SteamCMD**, sobreposto com **ReHLDS**, depois Metamod-R, ReGameDLL_CS, AMX Mod X e ReAPI. ReHLDS é compatível com a edição pré-aniversário do HLDS (build 8684 ou inferior); não deve ser instalado sobre versões antigas obtidas por `hldsupdatetool`.

O projeto **não deve usar SteamID como chave primária**. A chave do jogador é um UUID interno. SteamID e identificadores de clientes são apenas identidades vinculadas a essa conta.

## 2. Correções aplicadas à ideia inicial

| Ideia inicial | Correção de arquitetura | Motivo |
|---|---|---|
| SteamID como chave primária | `players.id` UUID como chave interna | Clientes sem autenticação podem ter IDs gerados ou instáveis; não são uma prova de identidade. |
| Plugin altera saldo diretamente | Toda alteração passa por uma transação e gera um lançamento no livro-caixa | Evita duplicação, fraude e saldo sem histórico. |
| Saldo e pagamentos no AMXX | AMXX somente consulta perfil/inventário e solicita compra; backend trata pagamentos | Pawn não é local apropriado para segredos, webhooks ou regras financeiras. |
| Banco acessível pelo painel e pelo jogo | Banco privado; usuários SQL e permissões separados | Reduz o impacto de vazamento de credenciais. |
| Baixar muitos assets e ativar | Pipeline de validação e publicação de assets | Modelos ou dependências ruins causam falha de download, kick ou crash. |
| Dar admin por SteamID/nome | Administração via conta web vinculada e permissões RBAC | Nome, IP e IDs não verificados podem ser falsificados ou mudar. |

## 3. Compatibilidade e identidade do jogador

O servidor pode suportar os tipos de cliente compatíveis com a configuração escolhida. Porém, compatibilidade de conexão não equivale a autenticação confiável.

- Uma conta Steam autenticada pode ser vinculada automaticamente a uma conta interna.
- Um cliente sem identidade Steam verificável deve começar como **não verificado**.
- Para vincular uma conta não verificada, o painel gera um código de uso único; o jogador o confirma no jogo (`/vincular CODIGO`) ou por fluxo web equivalente.
- Itens pagos, transferências de saldo, estornos e permissões administrativas exigem uma conta vinculada e verificada no painel.
- Nunca use IP, nickname ou o identificador gerado pela camada de compatibilidade como autorização para administração ou movimentação financeira.

### Estados de conta

| Estado | Pode jogar | Pode ganhar XP | Pode equipar item gratuito | Pode usar saldo pago | Pode ser admin |
|---|---:|---:|---:|---:|---:|
| Visitante | Sim | Sim | Sim | Não | Não |
| Vinculada | Sim | Sim | Sim | Sim | Não |
| Verificada | Sim | Sim | Sim | Sim | Sim, se receber papel |
| Suspensa | Não | Não | Não | Não | Não |

## 4. Arquitetura aprovada

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
  | plugin de perfil e inventário |           |
  +---------------+---------------+   +-------v--------+
                  |                   | FastAPI        |
                  | SQL privado        | painel + API   |
                  +---------+---------+-------+--------+
                            |                 |
                       +----v-----------------v----+
                       | PostgreSQL (rede privada) |
                       +---------------------------+

                 Nginx / FastDL -> apenas maps, models, sound
```

### Decisão de integração

No MVP, o plugin AMXX usa SQLx com um usuário SQL restrito para carregar perfil, inventário e registrar eventos de jogo. As consultas precisam ser assíncronas com `SQL_ThreadQuery`; consultas síncronas durante uma partida são proibidas.

O painel FastAPI usa um usuário de aplicação separado. O provedor de pagamento só conversa com o backend HTTPS. O plugin jamais recebe chave secreta de pagamento, senha de administrador global ou credencial com acesso total ao banco.

Uma API interna pode ser adicionada depois para operações específicas. Não é requisito do MVP, pois implementar HTTP/TLS completo e seguro em Pawn aumenta a complexidade e o risco.

## 5. Componentes e responsabilidades

| Componente | Responsável por | Não deve fazer |
|---|---|---|
| ReHLDS | motor, rede, estabilidade | regras de loja/pagamento |
| AMXX/ReAPI | comandos, menus, XP, equipar item | validar pagamento ou guardar segredos |
| PostgreSQL | dados transacionais e auditoria | ficar exposto à internet |
| FastAPI | painel, RBAC, catálogo, pagamentos, webhooks | controlar a partida em tempo real |
| Nginx FastDL | entrega de arquivos públicos compactados | servir `addons`, configs, backups ou código |
| Worker opcional | emails, conciliação, tarefas agendadas | executar comandos de jogo sem autorização |

## 6. Estrutura de repositório

```text
cs16-platform/
├── docs/
│   ├── AUDITORIA_PROJETO.md
│   ├── arquitetura.md
│   ├── api.md
│   └── runbook-operacao.md
├── game-server/
│   ├── cstrike/addons/amxmodx/scripting/
│   ├── cstrike/addons/amxmodx/configs/
│   ├── cstrike/models/
│   ├── cstrike/maps/
│   └── manifests/assets.json
├── backend/
│   ├── app/
│   │   ├── api/
│   │   ├── services/
│   │   ├── models/
│   │   ├── security/
│   │   └── main.py
│   ├── migrations/
│   └── tests/
├── admin-panel/
├── infrastructure/
│   ├── compose.yaml
│   ├── nginx/
│   ├── systemd/
│   └── backups/
├── fastdl-public/
│   └── cstrike/{maps,models,sound}/
├── .env.example
└── README.md
```

Arquivos `.env`, senhas, dumps SQL, binários baixados e assets licenciados não devem entrar no Git. O repositório deve conter apenas `.env.example`, manifests e instruções reproduzíveis.

## 7. Modelo de dados mínimo

```text
players
  id UUID PK
  display_name
  level INT
  xp BIGINT
  rank VARCHAR
  status VARCHAR
  created_at, updated_at

player_identities
  id UUID PK
  player_id UUID FK -> players.id
  provider VARCHAR                 -- steam, client, web
  external_id VARCHAR
  verified_at TIMESTAMP NULL
  UNIQUE(provider, external_id)

wallets
  player_id UUID PK/FK
  balance BIGINT                   -- menor unidade monetária; nunca float
  updated_at

wallet_transactions
  id UUID PK
  player_id UUID FK
  type VARCHAR                     -- topup, purchase, refund, adjustment
  amount BIGINT                    -- positivo ou negativo
  currency VARCHAR
  idempotency_key UUID UNIQUE
  reference_id VARCHAR UNIQUE NULL
  created_at

items
  id UUID PK
  sku VARCHAR UNIQUE
  item_type VARCHAR                -- weapon_skin, player_model
  price BIGINT
  asset_version VARCHAR
  enabled BOOLEAN

inventory_items
  player_id UUID FK
  item_id UUID FK
  acquired_transaction_id UUID FK
  equipped BOOLEAN
  PRIMARY KEY(player_id, item_id)

payment_orders
  id UUID PK
  player_id UUID FK
  provider VARCHAR
  provider_reference VARCHAR UNIQUE
  amount BIGINT
  status VARCHAR
  webhook_payload JSONB
  created_at, confirmed_at

admin_roles / admin_audit_logs
  papéis, concessões e registro de toda ação privilegiada
```

### Regras obrigatórias de consistência

1. Valor monetário é inteiro em centavos; nunca `float`.
2. Uma confirmação de pagamento cria no máximo uma transação de crédito para cada `provider_reference`.
3. Uma compra executa em transação: validar saldo, debitar, registrar `wallet_transactions`, conceder item.
4. Estorno não apaga registros: gera lançamento compensatório.
5. Alteração manual de saldo exige motivo, administrador responsável e log de auditoria.

## 8. Sistema de nível e status

Os nomes são uma apresentação calculada a partir de XP/nível; não são a fonte de permissão.

| Faixa sugerida | Status |
|---:|---|
| 1–9 | Iniciante |
| 10–24 | Amador |
| 25–49 | Competente |
| 50–74 | Veterano |
| 75+ | Elite |

XP deve ser ganho por eventos simples e auditáveis inicialmente: finalizar rodada, vitória, objetivo e participação. Evite recompensar somente kills; isso incentiva comportamento ruim e torna o balanceamento mais difícil.

## 9. Assets, mapas e FastDL

Todo asset entra por um registro de catálogo contendo: SKU, origem, autor quando conhecido, licença/termo aplicável, versão, tamanho, lista de arquivos e hash SHA-256.

Pipeline de publicação:

1. Download manual do asset, respeitando os termos de origem.
2. Varredura antimalware e inspeção do arquivo compactado.
3. Teste em servidor local com cliente limpo.
4. Conferência de dependências (`.mdl`, texturas, `.wav`, `.wad`, `.res`).
5. Cálculo de hash e atualização de `manifests/assets.json`.
6. Publicação no diretório do jogo e no FastDL.
7. Compactação compatível e teste de download real.
8. Ativação gradual em produção, com plano de rollback.

Restrições:

- Não publique arquivos de terceiros sem revisar os termos e a autoria.
- Não replique o catálogo do fornecedor em outro site ou host de arquivos.
- Não adicione dezenas de modelos em uma única atualização: limites de precache e download são sensíveis no GoldSrc.
- Use nomes curtos, estáveis, sem espaços e sem troca de caminho após um item ser vendido.
- Mapa customizado deve incluir todas as dependências no FastDL; o `.bsp` sozinho raramente basta.

## 10. Segurança

### Servidor Linux

- Criar usuário de serviço sem login administrativo; nunca executar HLDS como `root`.
- Após confirmar acesso por chave, desabilitar autenticação SSH por senha e login direto de root.
- Configurar firewall com portas mínimas: SSH restrito, UDP do jogo e HTTP/HTTPS quando necessário.
- PostgreSQL limitado a `127.0.0.1` ou rede privada; sem porta pública.
- Atualizar o sistema antes da instalação e configurar backups automatizados.
- Usar systemd com reinício controlado e limites de recursos.

### Aplicação e painel

- Senhas com Argon2id ou bcrypt; sessões HTTP seguras, expiráveis e protegidas contra CSRF.
- RBAC mínimo: `owner`, `administrator`, `moderator`, `support`, `player`.
- 2FA obrigatório para `owner` e administradores.
- Logs de login, alteração de saldo, concessão de item, banimento e mudança de papel.
- Rate limit em login, geração de PIX, webhook e endpoints administrativos.
- Validar assinatura de cada webhook e consultar o provedor quando houver divergência.
- Backup criptografado e teste mensal de restauração.

### Segredos

- Guardar segredos somente no servidor, fora do Git, em permissões de arquivo restritas.
- Usar credenciais diferentes para: banco do jogo, backend, migrações, backup e pagamento.
- Rotacionar segredos se forem expostos em chat, logs ou repositório.

## 11. Operação no notebook

O notebook informado está em Ubuntu 24.04 e foi acessado por SSH na rede local. O snapshot mostra uso de memória em torno de 83%; antes de instalar banco, painel e servidor, medir consumo real com `free -h`, `htop` e `systemctl --failed`.

Requisitos operacionais:

- Preferir cabo Ethernet; Wi-Fi piora estabilidade e latência.
- Reservar o IP local no roteador.
- Configurar encaminhamento da porta UDP do jogo somente se o servidor for público.
- Considerar CGNAT e IP dinâmico: ambos podem impedir acesso externo.
- Aceitar que conexão residencial e notebook não oferecem proteção prática contra DDoS; se o público crescer, migrar o servidor de jogo para VPS/hosting especializado.
- Monitorar temperatura, uso de RAM, espaço, reinícios e logs. Não operar próximo ao limite de memória.

## 12. Plano de implantação

### Fase 0 — preparação

- Atualizar Ubuntu e instalar dependências de 32 bits necessárias ao servidor.
- Criar usuário de serviço, diretórios, firewall, SSH por chave e rotina de backup.
- Definir domínio, se haverá acesso externo e política de privacidade/termos do servidor.

### Fase 1 — servidor jogável

- Instalar HLDS via SteamCMD e validar a versão legada.
- Instalar ReHLDS, Metamod-R, ReGameDLL_CS, AMX Mod X e ReAPI nessa ordem.
- Criar `systemd` service, logs rotacionados e mapa padrão.
- Testar conexão local e de outro computador da LAN.

### Fase 2 — FastDL e assets

- Configurar Nginx com raiz exclusiva para FastDL.
- Publicar um mapa e uma skin de teste.
- Validar download usando cliente limpo e testar rollback.

### Fase 3 — perfil e progressão

- Subir PostgreSQL privado e aplicar migrations.
- Criar plugin Pawn de perfil com carregamento assíncrono e cache somente por sessão.
- Implementar XP, níveis e comando `/perfil`.

### Fase 4 — inventário e loja sem dinheiro real

- Criar catálogo e equipar itens adquiridos por teste/admin.
- Implementar `/loja`, confirmação de compra e transação SQL atômica.
- Testar concorrência: duas compras simultâneas não podem duplicar item nem tornar saldo negativo.

### Fase 5 — painel e administração

- Implementar autenticação, 2FA administrativo, RBAC e trilha de auditoria.
- Criar telas de jogadores, itens, inventário, transações, bans e logs.

### Fase 6 — pagamentos

- Escolher provedor de pagamento com suporte adequado a PIX/webhooks.
- Implementar pedidos, confirmação assinada, idempotência, conciliação e estorno.
- Fazer testes de sandbox antes de qualquer cobrança real.

## 13. Critérios de aceite

O projeto não deve avançar de fase enquanto todos os itens da fase atual não passarem.

- [ ] Servidor reinicia automaticamente e não roda como root.
- [ ] Banco não é acessível da internet.
- [ ] Cliente limpo baixa mapa/asset pelo FastDL e entra normalmente.
- [ ] Consulta lenta ao banco não trava a rodada.
- [ ] Reconectar não cria contas, XP, saldo ou inventário duplicados.
- [ ] Compra é atômica e idempotente.
- [ ] Conta não autenticada não assume conta/admin de outro jogador.
- [ ] Toda alteração manual de saldo gera log imutável.
- [ ] Webhook inválido, repetido ou com valor divergente não concede saldo.
- [ ] Backup restaura com sucesso em ambiente de teste.

## 14. Itens explicitamente fora do MVP

- Mercado entre jogadores.
- Saque ou conversão de saldo em dinheiro.
- Criptomoedas.
- Integração de pagamento diretamente no Pawn.
- Sincronização automática de catálogos de sites de terceiros.
- Vários servidores compartilhando economia sem fila/eventos e testes de concorrência.

## 15. Próxima ação recomendada

Criar o repositório com esta estrutura e executar somente a Fase 0 e a Fase 1. O primeiro código a ser produzido deve ser um plugin mínimo de perfil (carregar UUID, XP e nível de modo assíncrono), acompanhado de migrations e testes de reconexão. Loja, skins pagas e pagamentos entram apenas depois que a identidade e o ledger estiverem comprovadamente corretos.

## Referências verificadas

- ReHLDS: https://rehlds.dev/docs/rehlds/install/
- ReHLDS GitHub: https://github.com/rehlds/rehlds
- ReUnion, configuração de identificação: https://github.com/rehlds/ReUnion/blob/master/reunion/dist/reunion.cfg
- AMX Mod X, `SQL_ThreadQuery`: https://amxmodx.org/api/sqlx/SQL_ThreadQuery
- CS16Forge, termos: https://cs16forge.com/terms/
- CS16Forge, guia de instalação de assets: https://cs16forge.com/guides/how-to-install-skins-models-maps-cs-16/
