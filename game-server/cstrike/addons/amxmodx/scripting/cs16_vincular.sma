#include <amxmodx>
#include <amxmisc>
#include <sqlx>

// cs16_vincular.sma
// Permite ao jogador vincular sua conta Steam a uma conta web
// usando um código de uso único gerado pelo painel (seção 3 da auditoria).

#define PLUGIN  "Vieira-STRIKE Vincular"
#define VERSION "1.0.0"
#define AUTHOR  "Vieira-STRIKE"

new Handle:g_sql

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_clcmd("say /vincular", "cmd_vincular")
    register_clcmd("say_team /vincular", "cmd_vincular")
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

public cmd_vincular(id) {
    new args[32]
    read_args(args, charsmax(args))
    remove_quotes(args)
    trim(args)

    if (!args[0]) {
        client_print(id, print_chat, "[Vieira-STRIKE] Uso: /vincular CODIGO  (obtenha o codigo no painel web)")
        return PLUGIN_HANDLED
    }

    // Código deve ter exatamente 8 caracteres alfanuméricos
    if (strlen(args) != 8) {
        client_print(id, print_chat, "[Vieira-STRIKE] Codigo invalido. Deve ter 8 caracteres.")
        return PLUGIN_HANDLED
    }

    new uuid[37]
    perfil_get_uuid(id, uuid, charsmax(uuid))
    if (!uuid[0]) {
        client_print(id, print_chat, "[Vieira-STRIKE] Perfil ainda carregando. Tente em instantes.")
        return PLUGIN_HANDLED
    }

    // Tenta consumir o código e vincular a conta
    // link_codes: (code VARCHAR PK, player_id UUID FK, expires_at TIMESTAMP, used_at TIMESTAMP NULL)
    new query[512]
    formatex(query, charsmax(query),
        "UPDATE link_codes \
         SET used_at = NOW() \
         WHERE code = '%s' \
           AND player_id = '%s' \
           AND used_at IS NULL \
           AND expires_at > NOW()",
        args, uuid)

    new data[2]
    data[0] = id
    data[1] = get_user_userid(id)
    SQL_ThreadQuery(g_sql, "cb_vincular", query, data, 2)

    return PLUGIN_HANDLED
}

public cb_vincular(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    new id  = data[0]
    new uid = data[1]
    if (get_user_userid(id) != uid) return

    if (failstate != TQUERY_SUCCESS) {
        client_print(id, print_chat, "[Vieira-STRIKE] Erro ao vincular. Tente novamente.")
        log_amx("[Vieira-STRIKE Vincular] Erro: %s", error)
        return
    }

    if (SQL_AffectedRows(query) > 0) {
        client_print(id, print_chat, "[Vieira-STRIKE] Conta vinculada com sucesso!")
        // Recarrega perfil para atualizar status
        perfil_recarregar(id)
    } else {
        client_print(id, print_chat, "[Vieira-STRIKE] Codigo invalido, expirado ou ja utilizado.")
    }
}

native perfil_get_uuid(id, dest[], len)
native perfil_recarregar(id)
