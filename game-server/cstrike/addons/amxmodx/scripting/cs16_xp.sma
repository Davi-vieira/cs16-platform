#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <cstrike>
#include <reapi>

// cs16_xp.sma
// Concede XP por eventos auditáveis: rodada, vitória, objetivo, participação.
// Nunca recompensa somente kills (seção 8 da auditoria).

#define PLUGIN  "Vieira-STRIKE XP"
#define VERSION "1.0.0"
#define AUTHOR  "Vieira-STRIKE"

// XP por evento
#define XP_PARTICIPACAO   5
#define XP_VITORIA       15
#define XP_OBJETIVO      20   // plantar/desarmar bomba, resgatar refém
#define XP_KILL           3   // bônus pequeno, não é o foco

// XP necessário para subir de nível: base * level^1.5
#define XP_BASE         100

new Handle:g_sql
new g_xp_pendente[33]   // acumula XP na rodada, salva no fim

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)
    RegisterHookChain(RG_RoundEnd, "ev_round_end", false)
    register_event("DeathMsg", "ev_kill", "a")
    RegisterHookChain(RG_CBasePlayer_Killed, "ev_killed", false)
    RegisterHookChain(RG_CBasePlayer_PlantBomb, "ev_objetivo", false)
    RegisterHookChain(RG_CBasePlayer_DefuseBomb, "ev_objetivo", false)
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

public client_disconnect(id) {
    g_xp_pendente[id] = 0
}

public ev_round_end(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay) {
    new players[32], count
    get_players(players, count, "a")

    for (new i = 0; i < count; i++) {
        new id = players[i]
        if (!perfil_carregado(id)) continue

        new xp = XP_PARTICIPACAO + g_xp_pendente[id]

        // Bônus de vitória
        new team = get_user_team(id)
        if ((status == WINSTATUS_CTS   && team == CS_TEAM_CT) ||
            (status == WINSTATUS_TERRORISTS && team == CS_TEAM_T)) {
            xp += XP_VITORIA
        }

        xp_conceder(id, xp, "round_end")
        g_xp_pendente[id] = 0
    }
}

public ev_objetivo(id) {
    if (!perfil_carregado(id)) return
    g_xp_pendente[id] += XP_OBJETIVO
}

public ev_kill() {
    new killer = read_data(1)
    new victim = read_data(2)
    if (killer == victim || killer < 1 || killer > 32) return
    if (!perfil_carregado(killer)) return
    g_xp_pendente[killer] += XP_KILL
}

xp_conceder(id, amount, const motivo[]) {
    if (amount <= 0) return

    new uuid[37]
    perfil_get_uuid(id, uuid, charsmax(uuid))
    if (!uuid[0]) return

    new query[512]
    formatex(query, charsmax(query),
        "UPDATE players SET \
            xp    = xp + %d, \
            level = GREATEST(1, FLOOR(POWER(xp + %d, 0.6667) / %d)::INT), \
            updated_at = NOW() \
         WHERE id = '%s'",
        amount, amount, XP_BASE, uuid)

    new data[2]
    data[0] = id
    data[1] = get_user_userid(id)
    SQL_ThreadQuery(g_sql, "cb_xp_salvo", query, data, 2)

    log_amx("[Vieira-STRIKE XP] id=%d uuid=%s +%d xp motivo=%s", id, uuid, amount, motivo)
}

public cb_xp_salvo(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    if (failstate != TQUERY_SUCCESS)
        log_amx("[Vieira-STRIKE XP] Erro ao salvar XP: %s", error)
}

// Declarações externas do plugin de perfil (resolvidas em tempo de link)
native bool:perfil_carregado(id)
native perfil_get_uuid(id, dest[], len)
