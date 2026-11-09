#include <amxmodx>
#include <amxmisc>
#include <sqlx>

// cs16_inventario.sma
// Carrega inventário do jogador e aplica itens equipados.
// Não valida pagamento — isso é responsabilidade do backend.

#define PLUGIN  "Vieira-STRIKE Inventario"
#define VERSION "1.0.0"
#define AUTHOR  "Vieira-STRIKE"

#define MAX_ITEMS    32
#define MAX_SKU      32
#define MAX_ITEMTYPE 24

enum _:ItemSlot {
    IS_ITEM_ID[37],
    IS_SKU[MAX_SKU],
    IS_TYPE[MAX_ITEMTYPE],
    bool:IS_EQUIPPED
}

new g_inv[33][MAX_ITEMS][ItemSlot]
new g_inv_count[33]
new Handle:g_sql

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_clcmd("say /inventario", "cmd_inventario")
    register_clcmd("say_team /inventario", "cmd_inventario")
    register_event("ResetHUD", "ev_spawn", "be")
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
}

public client_authorized(id) {
    inventario_carregar(id)
}

public client_disconnect(id) {
    g_inv_count[id] = 0
}

inventario_carregar(id) {
    new uuid[37]
    perfil_get_uuid(id, uuid, charsmax(uuid))
    if (!uuid[0]) {
        set_task(2.0, "inventario_carregar_delayed", id)
        return
    }

    new query[512]
    formatex(query, charsmax(query),
        "SELECT ii.item_id, i.sku, i.item_type, ii.equipped \
         FROM inventory_items ii \
         JOIN items i ON i.id = ii.item_id \
         WHERE ii.player_id = '%s' AND i.enabled = TRUE",
        uuid)

    new data[2]
    data[0] = id
    data[1] = get_user_userid(id)
    SQL_ThreadQuery(g_sql, "cb_inventario_carregado", query, data, 2)
}

public inventario_carregar_delayed(id) {
    inventario_carregar(id)
}

public cb_inventario_carregado(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    new id  = data[0]
    new uid = data[1]
    if (get_user_userid(id) != uid) return
    if (failstate != TQUERY_SUCCESS) {
        log_amx("[Vieira-STRIKE Inv] Erro ao carregar inventario: %s", error)
        return
    }

    g_inv_count[id] = 0
    while (SQL_MoreResults(query) && g_inv_count[id] < MAX_ITEMS) {
        new slot = g_inv_count[id]
        SQL_ReadResult(query, 0, g_inv[id][slot][IS_ITEM_ID], 36)
        SQL_ReadResult(query, 1, g_inv[id][slot][IS_SKU],     MAX_SKU - 1)
        SQL_ReadResult(query, 2, g_inv[id][slot][IS_TYPE],    MAX_ITEMTYPE - 1)
        g_inv[id][slot][IS_EQUIPPED] = bool:SQL_ReadResult(query, 3)
        g_inv_count[id]++
        SQL_NextRow(query)
    }
}

public ev_spawn(id) {
    if (!is_user_alive(id)) return
    aplicar_itens_equipados(id)
}

aplicar_itens_equipados(id) {
    for (new i = 0; i < g_inv_count[id]; i++) {
        if (!g_inv[id][i][IS_EQUIPPED]) continue

        new tipo[MAX_ITEMTYPE]
        copy(tipo, charsmax(tipo), g_inv[id][i][IS_TYPE])

        if (equal(tipo, "player_model")) {
            cs_set_user_model(id, g_inv[id][i][IS_SKU])
        }
        // weapon_skin: implementar via ReAPI quando assets estiverem no FastDL
    }
}

public cmd_inventario(id) {
    if (g_inv_count[id] == 0) {
        client_print(id, print_chat, "[Vieira-STRIKE] Seu inventario esta vazio.")
        return PLUGIN_HANDLED
    }
    client_print(id, print_chat, "[Vieira-STRIKE] Voce tem %d item(ns). Use /loja para comprar mais.", g_inv_count[id])
    return PLUGIN_HANDLED
}

native perfil_get_uuid(id, dest[], len)
native bool:perfil_carregado(id)
