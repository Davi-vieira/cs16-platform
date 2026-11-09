#include <amxmodx>
#include <amxmisc>
#include <sqlx>

// cs16_loja.sma
// Exibe catálogo e processa compra em transação atômica.
// Regra: validar saldo → debitar → registrar wallet_transactions → conceder item.
// Nunca usa float para valores monetários.

#define PLUGIN  "Vieira-STRIKE Loja"
#define VERSION "1.0.0"
#define AUTHOR  "Vieira-STRIKE"

#define MAX_CATALOG  32
#define MAX_SKU      32
#define MAX_ITEMNAME 48

enum _:CatalogItem {
    CI_ID[37],
    CI_SKU[MAX_SKU],
    CI_NAME[MAX_ITEMNAME],
    CI_TYPE[24],
    CI_PRICE   // centavos (inteiro)
}

new g_catalog[MAX_CATALOG][CatalogItem]
new g_catalog_count
new Handle:g_sql

// Compra pendente por jogador
new g_compra_item[33]   // índice no catálogo
new bool:g_compra_ativa[33]

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_clcmd("say /loja",      "cmd_loja")
    register_clcmd("say_team /loja", "cmd_loja")
    register_menucmd(register_menuid("cs16_loja"), (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8)|(1<<9), "menu_loja_handler")
}

public plugin_cfg() {
    new host[64], user[32], pass[32], db[32]
    SQL_SetAffinity("pgsql")
    get_cvar_string("amx_sql_host", host, charsmax(host))
    get_cvar_string("amx_sql_user", user, charsmax(user))
    get_cvar_string("amx_sql_pass", pass, charsmax(pass))
    get_cvar_string("amx_sql_db",   db,   charsmax(db))
    if (!host[0]) copy(host, charsmax(host), "127.0.0.1")
    if (!user[0]) copy(user, charsmax(user), "cs16_game")
    if (!db[0])   copy(db,   charsmax(db),   "cs16")
    g_sql = SQL_MakeDbTuple(host, user, pass, db)
    catalogo_carregar()
}

catalogo_carregar() {
    SQL_ThreadQuery(g_sql, "cb_catalogo",
        "SELECT id, sku, display_name, item_type, price \
         FROM items WHERE enabled = TRUE ORDER BY price ASC LIMIT 32",
        _, 0)
}

public cb_catalogo(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    if (failstate != TQUERY_SUCCESS) {
        log_amx("[Vieira-STRIKE Loja] Erro ao carregar catalogo: %s", error)
        return
    }
    g_catalog_count = 0
    while (SQL_MoreResults(query) && g_catalog_count < MAX_CATALOG) {
        new i = g_catalog_count
        SQL_ReadResult(query, 0, g_catalog[i][CI_ID],    36)
        SQL_ReadResult(query, 1, g_catalog[i][CI_SKU],   MAX_SKU - 1)
        SQL_ReadResult(query, 2, g_catalog[i][CI_NAME],  MAX_ITEMNAME - 1)
        SQL_ReadResult(query, 3, g_catalog[i][CI_TYPE],  23)
        g_catalog[i][CI_PRICE] = SQL_ReadResult(query, 4)
        g_catalog_count++
        SQL_NextRow(query)
    }
    log_amx("[Vieira-STRIKE Loja] %d itens carregados.", g_catalog_count)
}

public cmd_loja(id) {
    if (!perfil_carregado(id)) {
        client_print(id, print_chat, "[Vieira-STRIKE] Aguarde o carregamento do seu perfil.")
        return PLUGIN_HANDLED
    }
    if (g_catalog_count == 0) {
        client_print(id, print_chat, "[Vieira-STRIKE] Loja sem itens no momento.")
        return PLUGIN_HANDLED
    }
    mostrar_menu_loja(id, 0)
    return PLUGIN_HANDLED
}

mostrar_menu_loja(id, pagina) {
    new menu[1024], item_str[64]
    new inicio = pagina * 8
    new fim = min(inicio + 8, g_catalog_count)

    copy(menu, charsmax(menu), "\yVieira-STRIKE Loja\w\n\n")

    for (new i = inicio; i < fim; i++) {
        formatex(item_str, charsmax(item_str), "%s - R$ %d,%02d\n",
            g_catalog[i][CI_NAME],
            g_catalog[i][CI_PRICE] / 100,
            g_catalog[i][CI_PRICE] mod 100)
        add(menu, charsmax(menu), item_str)
    }

    if (fim < g_catalog_count) add(menu, charsmax(menu), "\n9. Proxima pagina\n")
    add(menu, charsmax(menu), "\n0. Fechar")

    show_menu(id, (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8)|(1<<9),
        menu, -1, "cs16_loja")
}

public menu_loja_handler(id, key) {
    if (key == 9) { mostrar_menu_loja(id, 0); return PLUGIN_HANDLED }
    if (key == 0) return PLUGIN_HANDLED

    new idx = key - 1
    if (idx < 0 || idx >= g_catalog_count) return PLUGIN_HANDLED

    confirmar_compra(id, idx)
    return PLUGIN_HANDLED
}

confirmar_compra(id, item_idx) {
    new menu[512]
    formatex(menu, charsmax(menu),
        "\yConfirmar compra?\w\n\n%s\nPreco: R$ %d,%02d\n\n1. Confirmar\n0. Cancelar",
        g_catalog[item_idx][CI_NAME],
        g_catalog[item_idx][CI_PRICE] / 100,
        g_catalog[item_idx][CI_PRICE] mod 100)

    g_compra_item[id]  = item_idx
    g_compra_ativa[id] = true
    show_menu(id, (1<<0)|(1<<1), menu, -1, "cs16_confirmar")
    register_menucmd(register_menuid("cs16_confirmar"), (1<<0)|(1<<1), "menu_confirmar_handler")
}

public menu_confirmar_handler(id, key) {
    if (!g_compra_ativa[id]) return PLUGIN_HANDLED
    g_compra_ativa[id] = false

    if (key != 1) {
        client_print(id, print_chat, "[Vieira-STRIKE] Compra cancelada.")
        return PLUGIN_HANDLED
    }

    executar_compra(id, g_compra_item[id])
    return PLUGIN_HANDLED
}

executar_compra(id, item_idx) {
    new uuid[37]
    perfil_get_uuid(id, uuid, charsmax(uuid))
    if (!uuid[0]) return

    new item_id[37]
    copy(item_id, charsmax(item_id), g_catalog[item_idx][CI_ID])
    new price = g_catalog[item_idx][CI_PRICE]

    // Transação atômica: verifica saldo, debita, registra, concede item
    // Idempotência: ON CONFLICT DO NOTHING em inventory_items
    new query[1024]
    formatex(query, charsmax(query),
        "DO $$ \
         DECLARE v_bal BIGINT; \
         BEGIN \
           SELECT balance INTO v_bal FROM wallets WHERE player_id = '%s' FOR UPDATE; \
           IF v_bal IS NULL OR v_bal < %d THEN \
             RAISE EXCEPTION 'saldo_insuficiente'; \
           END IF; \
           UPDATE wallets SET balance = balance - %d, updated_at = NOW() \
             WHERE player_id = '%s'; \
           INSERT INTO wallet_transactions \
             (id, player_id, type, amount, currency, idempotency_key) \
           VALUES \
             (gen_random_uuid(), '%s', 'purchase', -%d, 'BRL', gen_random_uuid()); \
           INSERT INTO inventory_items (player_id, item_id, equipped) \
           VALUES ('%s', '%s', FALSE) \
           ON CONFLICT DO NOTHING; \
         END $$",
        uuid, price,
        price, uuid,
        uuid, price,
        uuid, item_id)

    new data[3]
    data[0] = id
    data[1] = get_user_userid(id)
    data[2] = item_idx
    SQL_ThreadQuery(g_sql, "cb_compra_executada", query, data, 3)
}

public cb_compra_executada(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    new id  = data[0]
    new uid = data[1]
    new idx = data[2]
    if (get_user_userid(id) != uid) return

    if (failstate != TQUERY_SUCCESS) {
        if (containi(error, "saldo_insuficiente") != -1)
            client_print(id, print_chat, "[Vieira-STRIKE] Saldo insuficiente.")
        else
            client_print(id, print_chat, "[Vieira-STRIKE] Erro na compra. Tente novamente.")
        log_amx("[Vieira-STRIKE Loja] Erro na compra id=%d: %s", id, error)
        return
    }

    client_print(id, print_chat, "[Vieira-STRIKE] Compra realizada: %s", g_catalog[idx][CI_NAME])
    // Recarrega inventário para aplicar o item
    inventario_recarregar(id)
}

native bool:perfil_carregado(id)
native perfil_get_uuid(id, dest[], len)
native inventario_recarregar(id)
