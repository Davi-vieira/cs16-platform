#include <amxmodx>
#include <amxmisc>
#include <sqlx>

// cs16_perfil.sma
// Carrega perfil do jogador de forma assíncrona ao conectar.
// Nunca faz consulta síncrona durante partida.

#define PLUGIN  "Vieira-STRIKE Perfil"
#define VERSION "1.0.0"
#define AUTHOR  "Vieira-STRIKE"

#define MAX_UUID   37
#define MAX_NAME   64
#define MAX_STATUS 16

enum _:PlayerData {
    PD_UUID[MAX_UUID],
    PD_LEVEL,
    PD_XP,
    PD_STATUS[MAX_STATUS],
    bool:PD_LOADED
}

new g_player[33][PlayerData]
new Handle:g_sql

// Rank por nível (seção 8 da auditoria)
stock const g_ranks[][] = {
    "Iniciante", "Amador", "Competente", "Veterano", "Elite"
}

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    register_clcmd("say /perfil",  "cmd_perfil")
    register_clcmd("say_team /perfil", "cmd_perfil")
}

public plugin_cfg() {
    new host[64], user[32], pass[32], db[32]
    SQL_SetAffinity("pgsql")
    get_cvar_string("amx_sql_host", host, charsmax(host))
    get_cvar_string("amx_sql_user", user, charsmax(user))
    get_cvar_string("amx_sql_pass", pass, charsmax(pass))
    get_cvar_string("amx_sql_db",   db,   charsmax(db))

    // Lê do sql.cfg se cvars não definidos
    if (!host[0]) copy(host, charsmax(host), "127.0.0.1")
    if (!user[0]) copy(user, charsmax(user), "cs16_game")
    if (!db[0])   copy(db,   charsmax(db),   "cs16")

    g_sql = SQL_MakeDbTuple(host, user, pass, db)
}

public client_authorized(id) {
    perfil_carregar(id)
}

public client_disconnect(id) {
    g_player[id][PD_LOADED] = false
    g_player[id][PD_UUID]   = ""
    g_player[id][PD_LEVEL]  = 0
    g_player[id][PD_XP]     = 0
}

perfil_carregar(id) {
    new authid[36]
    get_user_authid(id, authid, charsmax(authid))

    new query[512]
    // Busca por identidade Steam; cria visitante se não existir
    formatex(query, charsmax(query),
        "SELECT p.id, p.level, p.xp, p.status \
         FROM players p \
         JOIN player_identities pi ON pi.player_id = p.id \
         WHERE pi.provider = 'steam' AND pi.external_id = '%s' \
         LIMIT 1",
        authid)

    new data[2]
    data[0] = id
    data[1] = get_user_userid(id)
    SQL_ThreadQuery(g_sql, "cb_perfil_carregado", query, data, 2)
}

public cb_perfil_carregado(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    new id   = data[0]
    new uid  = data[1]

    if (get_user_userid(id) != uid) return  // jogador saiu

    if (failstate != TQUERY_SUCCESS) {
        log_amx("[Vieira-STRIKE] Erro ao carregar perfil (id=%d): %s", id, error)
        return
    }

    if (SQL_NumResults(query) > 0) {
        SQL_ReadResult(query, 0, g_player[id][PD_UUID], MAX_UUID - 1)
        g_player[id][PD_LEVEL]  = SQL_ReadResult(query, 1)
        g_player[id][PD_XP]     = SQL_ReadResult(query, 2)
        SQL_ReadResult(query, 3, g_player[id][PD_STATUS], MAX_STATUS - 1)
        g_player[id][PD_LOADED] = true
    } else {
        // Jogador sem conta — cria como visitante de forma assíncrona
        perfil_criar_visitante(id)
    }
}

perfil_criar_visitante(id) {
    new authid[36], name[MAX_NAME]
    get_user_authid(id, authid, charsmax(authid))
    get_user_name(id, name, charsmax(name))

    // Escapa nome para evitar injeção
    new safe_name[MAX_NAME * 2]
    copy(safe_name, charsmax(safe_name), name)

    new query[768]
    formatex(query, charsmax(query),
        "WITH novo AS ( \
            INSERT INTO players (display_name, level, xp, status) \
            VALUES ('%s', 1, 0, 'visitor') \
            RETURNING id \
        ) \
        INSERT INTO player_identities (player_id, provider, external_id) \
        SELECT id, 'steam', '%s' FROM novo",
        safe_name, authid)

    new data[2]
    data[0] = id
    data[1] = get_user_userid(id)
    SQL_ThreadQuery(g_sql, "cb_visitante_criado", query, data, 2)
}

public cb_visitante_criado(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    new id  = data[0]
    new uid = data[1]
    if (get_user_userid(id) != uid) return
    if (failstate != TQUERY_SUCCESS) {
        log_amx("[Vieira-STRIKE] Erro ao criar visitante: %s", error)
        return
    }
    // Recarrega perfil recém-criado
    perfil_carregar(id)
}

public cmd_perfil(id) {
    if (!g_player[id][PD_LOADED]) {
        client_print(id, print_chat, "[Vieira-STRIKE] Carregando seu perfil, aguarde...")
        return PLUGIN_HANDLED
    }

    new rank[16]
    nivel_para_rank(g_player[id][PD_LEVEL], rank, charsmax(rank))

    client_print(id, print_chat,
        "[Vieira-STRIKE] Nivel: %d | XP: %d | Rank: %s | Status: %s",
        g_player[id][PD_LEVEL],
        g_player[id][PD_XP],
        rank,
        g_player[id][PD_STATUS])

    return PLUGIN_HANDLED
}

stock nivel_para_rank(level, dest[], len) {
    if      (level < 10) copy(dest, len, g_ranks[0])
    else if (level < 25) copy(dest, len, g_ranks[1])
    else if (level < 50) copy(dest, len, g_ranks[2])
    else if (level < 75) copy(dest, len, g_ranks[3])
    else                 copy(dest, len, g_ranks[4])
}

// Acessores públicos para outros plugins
stock bool:perfil_carregado(id)         return g_player[id][PD_LOADED]
stock perfil_get_level(id)              return g_player[id][PD_LEVEL]
stock perfil_get_xp(id)                 return g_player[id][PD_XP]
stock perfil_get_uuid(id, dest[], len)  copy(dest, len, g_player[id][PD_UUID])
stock perfil_get_status(id, dest[], len) copy(dest, len, g_player[id][PD_STATUS])
