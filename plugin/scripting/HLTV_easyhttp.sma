#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <reapi>
#include <file>
#include <easy_http>
#include <amxconst>

#pragma dynamic 131072

#define PLUGIN  "HLTV Logger"
#define VERSION "1.6"
#define AUTHOR  "cultura"

#define MAX_PLAYERS         32
#define MAX_NAME_LEN        64
#define MAX_AUTH_LEN        64
#define MAX_STEAM64_LEN     32
#define MAX_WEAPON_LEN      32
#define MAX_CHAT_LEN        192
#define MAX_TYPE_LEN        32
#define MAX_TEAM_LEN        8
#define MAX_REASON_LEN      32
#define MAX_PATH_LEN        256
#define MAX_JSON_BUF        384
#define MAX_MATCH_ID_LEN    96
#define MAX_SAFE_API_BODY_LEN 12000

enum _:EventRec
{
    ER_TIME,
    ER_HEADSHOT,
    ER_DISTANCE100,
    ER_ATTACKER_NAME[MAX_NAME_LEN],
    ER_ATTACKER_AUTH[MAX_AUTH_LEN],
    ER_ATTACKER_STEAM64[MAX_STEAM64_LEN],
    ER_VICTIM_NAME[MAX_NAME_LEN],
    ER_VICTIM_AUTH[MAX_AUTH_LEN],
    ER_VICTIM_STEAM64[MAX_STEAM64_LEN],
    ER_WEAPON[MAX_WEAPON_LEN],
    ER_TYPE[MAX_TYPE_LEN]
}

enum _:ChatRec
{
    CR_TIME,
    CR_TEAMCHAT,
    CR_NAME[MAX_NAME_LEN],
    CR_AUTH[MAX_AUTH_LEN],
    CR_STEAM64[MAX_STEAM64_LEN],
    CR_MSG[MAX_CHAT_LEN]
}

enum _:PlayerRoundRec
{
    PR_NAME[MAX_NAME_LEN],
    PR_AUTH[MAX_AUTH_LEN],
    PR_STEAM64[MAX_STEAM64_LEN],
    PR_TEAM[MAX_TEAM_LEN],
    PR_KILLS,
    PR_DEATHS,
    PR_ASSISTS,
    PR_DAMAGE,
    PR_HEADSHOT_KILLS,
    PR_UTILITY_DAMAGE,
    PR_CASH_EARNED,
    PR_EQUIP_VALUE,
    PR_KILL_REWARD,
    PR_LIVE_TIME,
    PR_MONEY_SAVED,
    PR_OBJECTIVE,
    PR_ENEMIES_FLASHED,
    PR_PLANTS,
    PR_DEFUSES,
    PR_EXPLODES
}

new Array:g_Events;
new Array:g_Chats;
new Array:g_PlayerRounds;

new bool:g_MatchStarted;
new bool:g_RoundLive;
new bool:g_RoundClosed;

new g_MatchStartTime;
new g_MatchEndTime;
new g_MatchId;
new g_MatchUid[MAX_MATCH_ID_LEN];
new g_LastExportMatchId[MAX_MATCH_ID_LEN];
new g_CompletedRounds;
new g_CTScore;
new g_TScore;
new g_LastRoundStart;
new g_LastSavedCTScore;
new g_LastSavedTScore;

new g_RoundKills[MAX_PLAYERS + 1];
new g_RoundDeaths[MAX_PLAYERS + 1];
new g_RoundAssists[MAX_PLAYERS + 1];
new g_RoundDamage[MAX_PLAYERS + 1];
new g_RoundHSKills[MAX_PLAYERS + 1];
new g_RoundUtilityDamage[MAX_PLAYERS + 1];
new g_RoundPlants[MAX_PLAYERS + 1];
new g_RoundDefuses[MAX_PLAYERS + 1];
new g_RoundExplodes[MAX_PLAYERS + 1];

new g_PlayerRoundSpawnTime[MAX_PLAYERS + 1];
new g_PlayerRoundLiveTime[MAX_PLAYERS + 1];
new bool:g_PlayerRoundDead[MAX_PLAYERS + 1];

new g_RoundEventCount;
new g_RoundChatCount;
new g_RoundReason[MAX_REASON_LEN];
new g_LastBombPlanterName[MAX_NAME_LEN];
new g_LastBombPlanterAuth[MAX_AUTH_LEN];
new g_LastBombPlanterSteam64[MAX_STEAM64_LEN];

new g_TempRoundsPath[MAX_PATH_LEN];
new g_LastExportPath[MAX_PATH_LEN];
new g_IndexPath[MAX_PATH_LEN];

new g_pcvar_export_dir;
new g_pcvar_auto_export_end;
new g_pcvar_save_chat;
new g_pcvar_save_chat_cmds;
new g_pcvar_save_connects;
new g_pcvar_save_disconnects;
new g_pcvar_include_steam64;
new g_pcvar_reset_after_finalize;
new g_pcvar_demo_filename;
new g_pcvar_demo_path;
new g_pcvar_demo_provider;
new g_pcvar_json_retention_days;
new g_pcvar_server_uid;
new g_pcvar_api_enabled;
new g_pcvar_api_url;
new g_pcvar_api_key;
new g_pcvar_api_timeout;
new g_pcvar_api_auto_send_finalize;
new EzHttpQueue:g_ApiQueue;
new g_ApiBody[MAX_SAFE_API_BODY_LEN];

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");
    register_logevent("Event_RoundEnd", 2, "1=Round_End");

    register_event("DeathMsg", "Event_DeathMsg", "a");
    register_event("Damage", "Event_Damage", "b", "2!0");

    register_clcmd("say", "CmdSay");
    register_clcmd("say_team", "CmdSayTeam");

    register_concmd("amx_export_matchjson", "CmdExportSnapshot", ADMIN_RCON);
    register_concmd("amx_finalize_matchjson", "CmdFinalizeMatch", ADMIN_RCON);
    register_concmd("amx_reset_matchjson", "CmdResetMatch", ADMIN_RCON);
    register_concmd("amx_matchjson_status", "CmdStatus", ADMIN_RCON);
    register_concmd("amx_send_matchjson", "CmdSendMatchJson", ADMIN_RCON);

    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn_Post", true);

    g_pcvar_export_dir = register_cvar("mjl_export_dir", "");
    g_pcvar_auto_export_end = register_cvar("mjl_auto_export_on_plugin_end", "1");
    g_pcvar_save_chat = register_cvar("mjl_save_chat", "1");
    g_pcvar_save_chat_cmds = register_cvar("mjl_save_chat_commands", "0");
    g_pcvar_save_connects = register_cvar("mjl_save_connects", "1");
    g_pcvar_save_disconnects = register_cvar("mjl_save_disconnects", "1");
    g_pcvar_include_steam64 = register_cvar("mjl_include_steam64", "1");
    g_pcvar_reset_after_finalize = register_cvar("mjl_reset_after_finalize", "1");
    g_pcvar_demo_filename = register_cvar("mjl_demo_filename", "");
    g_pcvar_demo_path = register_cvar("mjl_demo_path", "");
    g_pcvar_demo_provider = register_cvar("mjl_demo_provider", "HLTV");
    g_pcvar_json_retention_days = register_cvar("mjl_json_retention_days", "3");
    g_pcvar_server_uid = register_cvar("mjl_server_uid", "");
    g_pcvar_api_enabled = register_cvar("mjl_api_enabled", "0");
    g_pcvar_api_url = register_cvar("mjl_api_url", "");
    g_pcvar_api_key = register_cvar("mjl_api_key", "");
    g_pcvar_api_timeout = register_cvar("mjl_api_timeout", "30");
    g_pcvar_api_auto_send_finalize = register_cvar("mjl_api_auto_send_finalize", "1");
    g_ApiQueue = ezhttp_create_queue();

    g_Events = ArrayCreate(EventRec);
    g_Chats = ArrayCreate(ChatRec);
    g_PlayerRounds = ArrayCreate(PlayerRoundRec);

    ResetMatchState();
    CleanupOldExports();
}

public plugin_end()
{
    if (g_RoundLive && !g_RoundClosed)
    {
        FinalizeRound();
    }

    if (g_MatchStarted && get_pcvar_num(g_pcvar_auto_export_end) != 0)
    {
        ExportMatchJson(true);
    }

    if (g_Events) ArrayDestroy(g_Events);
    if (g_Chats) ArrayDestroy(g_Chats);
    if (g_PlayerRounds) ArrayDestroy(g_PlayerRounds);
}

public plugin_log()
{
    if (!g_RoundLive)
        return PLUGIN_CONTINUE;

    new logline[256];
    read_logdata(logline, charsmax(logline));

    if (contain(logline, "Planted_The_Bomb") != -1)
    {
        HandleBombPlayerLog("Planted_The_Bomb", "bomb_planted", 1);
    }
    else if (contain(logline, "Defused_The_Bomb") != -1)
    {
        HandleBombPlayerLog("Defused_The_Bomb", "bomb_defused", 2);
    }
    else if (contain(logline, "Target_Bombed") != -1)
    {
        HandleBombExploded();
    }

    return PLUGIN_CONTINUE;
}

public client_putinserver(id)
{
    if (!IsTrackablePlayer(id))
        return;

    if (!g_MatchStarted || get_pcvar_num(g_pcvar_save_connects) == 0)
        return;

    AddSimpleEvent("player_connect", id, 0, "", false);
}

public client_disconnected(id)
{
    if (!g_MatchStarted || get_pcvar_num(g_pcvar_save_disconnects) == 0)
        return;

    if (is_user_hltv(id))
        return;

    new name[MAX_NAME_LEN], authRaw[MAX_AUTH_LEN], authNorm[MAX_AUTH_LEN], steam64[MAX_STEAM64_LEN];
    GetPlayerNameRaw(id, name, charsmax(name));
    GetPlayerAuthRaw(id, authRaw, charsmax(authRaw));
    NormalizeSteamId(authRaw, authNorm, charsmax(authNorm));
    SteamIdTo64(authNorm, steam64, charsmax(steam64));

    AddNamedEvent("player_disconnect", name, authNorm, steam64, "", "0", "0", "", false, 0.0);
}

public OnPlayerSpawn_Post(id)
{
    if (!IsTrackablePlayer(id) || !g_RoundLive)
        return HC_CONTINUE;

    g_PlayerRoundSpawnTime[id] = get_systime();
    g_PlayerRoundDead[id] = false;

    return HC_CONTINUE;
}

public Event_NewRound()
{
    new now = get_systime();

    if (now - g_LastRoundStart <= 1)
        return;

    g_LastRoundStart = now;

    if (g_RoundLive && !g_RoundClosed)
    {
        FinalizeRound();
    }

    if (!g_MatchStarted)
    {
        StartMatch();
    }

    g_RoundLive = true;
    g_RoundClosed = false;
    ResetRoundState();
}

public Event_RoundEnd()
{
    if (!g_RoundLive || g_RoundClosed)
        return;

    FinalizeRound();
}

public Event_DeathMsg()
{
    if (!g_RoundLive)
        return;

    new killer = read_data(1);
    new victim = read_data(2);
    new headshot = read_data(3);

    new weapon[MAX_WEAPON_LEN];
    read_data(4, weapon, charsmax(weapon));

    if (IsTrackablePlayer(victim))
    {
        g_RoundDeaths[victim]++;
        UpdateLiveTimeOnDeath(victim);
    }

    if (IsTrackablePlayer(killer) && killer != victim)
    {
        g_RoundKills[killer]++;
        if (headshot)
        {
            g_RoundHSKills[killer]++;
        }
    }

    AddDeathEvent(killer, victim, weapon, headshot);
}

public Event_Damage(victim)
{
    if (!g_RoundLive || !IsTrackablePlayer(victim))
        return;

    new damage = read_data(2);
    if (damage <= 0)
        return;

    new weapon, hitplace;
    new attacker = get_user_attacker(victim, weapon, hitplace);

    if (!IsTrackablePlayer(attacker) || attacker == victim)
        return;

    g_RoundDamage[attacker] += damage;

    if (weapon == CSW_HEGRENADE)
    {
        g_RoundUtilityDamage[attacker] += damage;
    }
}

public CmdSay(id)
{
    CaptureChat(id, false);
    return PLUGIN_CONTINUE;
}

public CmdSayTeam(id)
{
    CaptureChat(id, true);
    return PLUGIN_CONTINUE;
}

public CmdExportSnapshot(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    ExportMatchJson(false);
    console_print(id, "[matchjson] snapshot exported: %s", g_LastExportPath);
    return PLUGIN_HANDLED;
}

public CmdFinalizeMatch(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    if (g_RoundLive && !g_RoundClosed)
    {
        FinalizeRound();
    }

    ExportMatchJson(true);
    console_print(id, "[matchjson] finalized: %s", g_LastExportPath);

    if (get_pcvar_num(g_pcvar_api_enabled) != 0 && get_pcvar_num(g_pcvar_api_auto_send_finalize) != 0)
    {
        SendExportedJsonToApi(g_LastExportPath);
        console_print(id, "[matchjson] api send scheduled");
    }

    if (get_pcvar_num(g_pcvar_reset_after_finalize) != 0)
    {
        CleanupMatchFiles();
        ResetMatchState();
        console_print(id, "[matchjson] state reset");
    }

    return PLUGIN_HANDLED;
}

public CmdResetMatch(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    CleanupMatchFiles();
    ResetMatchState();
    console_print(id, "[matchjson] state reset");
    return PLUGIN_HANDLED;
}

public CmdStatus(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    console_print(id, "[matchjson] started=%d rounds=%d temp=%s export=%s", g_MatchStarted, g_CompletedRounds, g_TempRoundsPath, g_LastExportPath);
    return PLUGIN_HANDLED;
}

public CmdSendMatchJson(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    if (!g_LastExportPath[0] || !file_exists(g_LastExportPath))
    {
        console_print(id, "[matchjson] no exported json found");
        return PLUGIN_HANDLED;
    }

    SendExportedJsonToApi(g_LastExportPath);
    console_print(id, "[matchjson] send scheduled: %s", g_LastExportPath);
    return PLUGIN_HANDLED;
}

StartMatch()
{
    g_MatchStarted = true;
    g_MatchStartTime = get_systime();
    g_MatchEndTime = 0;
    g_MatchId = g_MatchStartTime;
    BuildMatchUid();
    g_LastSavedCTScore = get_member_game(m_iNumCTWins);
    g_LastSavedTScore = get_member_game(m_iNumTerroristWins);
    g_CTScore = g_LastSavedCTScore;
    g_TScore = g_LastSavedTScore;
    g_CompletedRounds = 0;

    BuildTempRoundsPath();
    BuildIndexPath();
    delete_file(g_TempRoundsPath);
}

FinalizeRound()
{
    g_RoundClosed = true;
    g_RoundLive = false;

    new currentCT = get_member_game(m_iNumCTWins);
    new currentT  = get_member_game(m_iNumTerroristWins);

    g_CTScore = currentCT;
    g_TScore = currentT;

    new bool:scoreChanged = false;
    if (currentCT != g_LastSavedCTScore || currentT != g_LastSavedTScore)
    {
        scoreChanged = true;
    }

    if (!ShouldKeepRound(scoreChanged))
    {
        g_LastSavedCTScore = currentCT;
        g_LastSavedTScore = currentT;
        ClearRoundBuffersOnly();
        return;
    }

    new winner[8], reason[MAX_REASON_LEN];
    DetermineRoundOutcome(currentCT, currentT, winner, charsmax(winner), reason, charsmax(reason));

    SnapshotRoundPlayers();
    AppendCurrentRoundToTemp(currentCT, currentT, winner, reason);

    g_LastSavedCTScore = currentCT;
    g_LastSavedTScore = currentT;
    g_CompletedRounds++;

    ClearRoundBuffersOnly();
}

bool:ShouldKeepRound(bool:scoreChanged)
{
    if (scoreChanged)
        return true;

    if (g_RoundEventCount > 0)
        return true;

    if (g_RoundChatCount > 0)
        return true;

    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (!IsTrackablePlayer(id))
            continue;

        if (g_RoundKills[id] > 0
        || g_RoundDeaths[id] > 0
        || g_RoundAssists[id] > 0
        || g_RoundDamage[id] > 0
        || g_RoundHSKills[id] > 0
        || g_RoundUtilityDamage[id] > 0
        || g_RoundPlants[id] > 0
        || g_RoundDefuses[id] > 0
        || g_RoundExplodes[id] > 0)
        {
            return true;
        }
    }

    return false;
}

DetermineRoundOutcome(currentCT, currentT, winner[], winnerLen, reason[], reasonLen)
{
    if (currentCT > g_LastSavedCTScore)
    {
        copy(winner, winnerLen, "CT");
    }
    else if (currentT > g_LastSavedTScore)
    {
        copy(winner, winnerLen, "T");
    }
    else
    {
        copy(winner, winnerLen, "DRAW");
    }

    if (g_RoundReason[0])
    {
        copy(reason, reasonLen, g_RoundReason);
        return;
    }

    new aliveCT = 0, aliveT = 0;
    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (!IsTrackablePlayer(id))
            continue;

        switch (cs_get_user_team(id))
        {
            case CS_TEAM_CT:
            {
                if (is_user_alive(id)) aliveCT++;
            }
            case CS_TEAM_T:
            {
                if (is_user_alive(id)) aliveT++;
            }
        }
    }

    if (aliveCT > 0 && aliveT == 0)
    {
        copy(reason, reasonLen, "elimination");
    }
    else if (aliveT > 0 && aliveCT == 0)
    {
        copy(reason, reasonLen, "elimination");
    }
    else if (equal(winner, "DRAW"))
    {
        copy(reason, reasonLen, "draw");
    }
    else
    {
        copy(reason, reasonLen, "time");
    }
}

ResetMatchState()
{
    g_MatchStarted = false;
    g_RoundLive = false;
    g_RoundClosed = false;
    g_MatchStartTime = 0;
    g_MatchEndTime = 0;
    g_MatchId = 0;
    g_MatchUid[0] = 0;
    g_CompletedRounds = 0;
    g_CTScore = 0;
    g_TScore = 0;
    g_LastRoundStart = 0;
    g_LastSavedCTScore = 0;
    g_LastSavedTScore = 0;
    g_TempRoundsPath[0] = 0;
    g_IndexPath[0] = 0;

    ResetRoundState();

    for (new i = 1; i <= MAX_PLAYERS; i++)
    {
        g_RoundKills[i] = 0;
        g_RoundDeaths[i] = 0;
        g_RoundAssists[i] = 0;
        g_RoundDamage[i] = 0;
        g_RoundHSKills[i] = 0;
        g_RoundUtilityDamage[i] = 0;
        g_RoundPlants[i] = 0;
        g_RoundDefuses[i] = 0;
        g_RoundExplodes[i] = 0;
        g_PlayerRoundSpawnTime[i] = 0;
        g_PlayerRoundLiveTime[i] = 0;
        g_PlayerRoundDead[i] = false;
    }
}

ResetRoundState()
{
    g_RoundEventCount = 0;
    g_RoundChatCount = 0;
    g_RoundReason[0] = 0;
    g_LastBombPlanterName[0] = 0;
    g_LastBombPlanterAuth[0] = 0;
    g_LastBombPlanterSteam64[0] = 0;

    for (new i = 1; i <= MAX_PLAYERS; i++)
    {
        g_RoundKills[i] = 0;
        g_RoundDeaths[i] = 0;
        g_RoundAssists[i] = 0;
        g_RoundDamage[i] = 0;
        g_RoundHSKills[i] = 0;
        g_RoundUtilityDamage[i] = 0;
        g_RoundPlants[i] = 0;
        g_RoundDefuses[i] = 0;
        g_RoundExplodes[i] = 0;
        g_PlayerRoundSpawnTime[i] = 0;
        g_PlayerRoundLiveTime[i] = 0;
        g_PlayerRoundDead[i] = false;

        if (IsTrackablePlayer(i) && is_user_alive(i))
        {
            g_PlayerRoundSpawnTime[i] = get_systime();
        }
    }

    ClearRoundBuffersOnly();
}

ClearRoundBuffersOnly()
{
    if (g_Events) ArrayClear(g_Events);
    if (g_Chats) ArrayClear(g_Chats);
    if (g_PlayerRounds) ArrayClear(g_PlayerRounds);
    g_RoundEventCount = 0;
    g_RoundChatCount = 0;
    g_RoundReason[0] = 0;
    g_LastBombPlanterName[0] = 0;
    g_LastBombPlanterAuth[0] = 0;
    g_LastBombPlanterSteam64[0] = 0;
}

SnapshotRoundPlayers()
{
    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (!IsTrackablePlayer(id))
            continue;

        new CsTeams:team = cs_get_user_team(id);
        if (team != CS_TEAM_T && team != CS_TEAM_CT)
            continue;

        if (!g_PlayerRoundDead[id] && g_PlayerRoundSpawnTime[id] > 0)
        {
            g_PlayerRoundLiveTime[id] += (get_systime() - g_PlayerRoundSpawnTime[id]);
        }

        new playerData[PlayerRoundRec];
        new authNorm[MAX_AUTH_LEN], steam64[MAX_STEAM64_LEN];

        GetPlayerNameSafe(id, playerData[PR_NAME], MAX_NAME_LEN - 1);
        GetPlayerAuthSafe(id, authNorm, charsmax(authNorm));
        copy(playerData[PR_AUTH], MAX_AUTH_LEN - 1, authNorm);
        FillSteam64Maybe(authNorm, steam64, charsmax(steam64));
        copy(playerData[PR_STEAM64], MAX_STEAM64_LEN - 1, steam64);
        GetPlayerTeamSafe(id, playerData[PR_TEAM], MAX_TEAM_LEN - 1);

        playerData[PR_KILLS] = g_RoundKills[id];
        playerData[PR_DEATHS] = g_RoundDeaths[id];
        playerData[PR_ASSISTS] = g_RoundAssists[id];
        playerData[PR_DAMAGE] = g_RoundDamage[id];
        playerData[PR_HEADSHOT_KILLS] = g_RoundHSKills[id];
        playerData[PR_UTILITY_DAMAGE] = g_RoundUtilityDamage[id];
        playerData[PR_CASH_EARNED] = 0;
        playerData[PR_EQUIP_VALUE] = 0;
        playerData[PR_KILL_REWARD] = 0;
        playerData[PR_LIVE_TIME] = g_PlayerRoundLiveTime[id];
        playerData[PR_MONEY_SAVED] = cs_get_user_money(id);
        playerData[PR_PLANTS] = g_RoundPlants[id];
        playerData[PR_DEFUSES] = g_RoundDefuses[id];
        playerData[PR_EXPLODES] = g_RoundExplodes[id];
        playerData[PR_OBJECTIVE] = g_RoundPlants[id] + g_RoundDefuses[id] + g_RoundExplodes[id];
        playerData[PR_ENEMIES_FLASHED] = 0;

        ArrayPushArray(g_PlayerRounds, playerData);
    }
}

CaptureChat(id, bool:isTeam)
{
    if (!g_MatchStarted || !IsTrackablePlayer(id) || get_pcvar_num(g_pcvar_save_chat) == 0)
        return;

    new msg[MAX_CHAT_LEN];
    read_args(msg, charsmax(msg));
    remove_quotes(msg);
    trim(msg);

    if (!msg[0])
        return;

    if (get_pcvar_num(g_pcvar_save_chat_cmds) == 0)
    {
        if (msg[0] == '/' || msg[0] == '!')
            return;
    }

    new chatData[ChatRec];
    new authNorm[MAX_AUTH_LEN], steam64[MAX_STEAM64_LEN];

    chatData[CR_TIME] = get_systime();
    chatData[CR_TEAMCHAT] = isTeam ? 1 : 0;

    GetPlayerNameSafe(id, chatData[CR_NAME], MAX_NAME_LEN - 1);
    GetPlayerAuthSafe(id, authNorm, charsmax(authNorm));
    copy(chatData[CR_AUTH], MAX_AUTH_LEN - 1, authNorm);
    FillSteam64Maybe(authNorm, steam64, charsmax(steam64));
    copy(chatData[CR_STEAM64], MAX_STEAM64_LEN - 1, steam64);
    copy(chatData[CR_MSG], MAX_CHAT_LEN - 1, msg);

    ArrayPushArray(g_Chats, chatData);
    g_RoundChatCount++;
}

HandleBombPlayerLog(const triggerNeedle[], const eventType[], objectiveType)
{
    new argc = read_logargc();
    if (argc <= 0)
        return;

    new logline[256];
    read_logdata(logline, charsmax(logline));
    if (contain(logline, triggerNeedle) == -1)
        return;

    new userlog[128], name[MAX_NAME_LEN], authRaw[MAX_AUTH_LEN], authNorm[MAX_AUTH_LEN], team[16], userid, steam64[MAX_STEAM64_LEN];
    read_logargv(0, userlog, charsmax(userlog));
    parse_loguser(userlog, name, charsmax(name), userid, authRaw, charsmax(authRaw), team, charsmax(team));

    NormalizeSteamId(authRaw, authNorm, charsmax(authNorm));
    FillSteam64Maybe(authNorm, steam64, charsmax(steam64));

    new id = FindPlayerByAuthOrName(authNorm, name);

    if (id > 0)
    {
        if (objectiveType == 1) g_RoundPlants[id]++;
        if (objectiveType == 2) g_RoundDefuses[id]++;

        AddSimpleEvent(eventType, id, 0, "c4", false);

        if (equal(eventType, "bomb_planted"))
        {
            copy(g_LastBombPlanterName, charsmax(g_LastBombPlanterName), name);
            copy(g_LastBombPlanterAuth, charsmax(g_LastBombPlanterAuth), authNorm);
            copy(g_LastBombPlanterSteam64, charsmax(g_LastBombPlanterSteam64), steam64);
        }

        if (equal(eventType, "bomb_defused"))
        {
            copy(g_RoundReason, charsmax(g_RoundReason), "bomb_defused");
        }
    }
    else
    {
        AddNamedEvent(eventType, name, authNorm, steam64, "", "0", "0", "c4", false, 0.0);

        if (equal(eventType, "bomb_planted"))
        {
            copy(g_LastBombPlanterName, charsmax(g_LastBombPlanterName), name);
            copy(g_LastBombPlanterAuth, charsmax(g_LastBombPlanterAuth), authNorm);
            copy(g_LastBombPlanterSteam64, charsmax(g_LastBombPlanterSteam64), steam64);
        }

        if (equal(eventType, "bomb_defused"))
        {
            copy(g_RoundReason, charsmax(g_RoundReason), "bomb_defused");
        }
    }
}

HandleBombExploded()
{
    copy(g_RoundReason, charsmax(g_RoundReason), "bomb_exploded");

    if (!g_LastBombPlanterName[0] && !g_LastBombPlanterAuth[0])
    {
        AddNamedEvent("bomb_exploded", "", "0", "0", "", "0", "0", "c4", false, 0.0);
        return;
    }

    new id = FindPlayerByAuthOrName(g_LastBombPlanterAuth, g_LastBombPlanterName);
    if (id > 0)
    {
        g_RoundExplodes[id]++;
        AddSimpleEvent("bomb_exploded", id, 0, "c4", false);
    }
    else
    {
        AddNamedEvent("bomb_exploded", g_LastBombPlanterName, g_LastBombPlanterAuth, g_LastBombPlanterSteam64, "", "0", "0", "c4", false, 0.0);
    }
}

AddSimpleEvent(const eventType[], player, victim, const weapon[], bool:headshot)
{
    new eventData[EventRec];
    new authNorm[MAX_AUTH_LEN], steam64[MAX_STEAM64_LEN];

    eventData[ER_TIME] = get_systime();
    eventData[ER_HEADSHOT] = headshot ? 1 : 0;
    eventData[ER_DISTANCE100] = 0;
    copy(eventData[ER_TYPE], MAX_TYPE_LEN - 1, eventType);

    if (IsTrackablePlayer(player))
    {
        GetPlayerNameSafe(player, eventData[ER_ATTACKER_NAME], MAX_NAME_LEN - 1);
        GetPlayerAuthSafe(player, authNorm, charsmax(authNorm));
        copy(eventData[ER_ATTACKER_AUTH], MAX_AUTH_LEN - 1, authNorm);
        FillSteam64Maybe(authNorm, steam64, charsmax(steam64));
        copy(eventData[ER_ATTACKER_STEAM64], MAX_STEAM64_LEN - 1, steam64);
    }
    else
    {
        eventData[ER_ATTACKER_NAME][0] = 0;
        copy(eventData[ER_ATTACKER_AUTH], MAX_AUTH_LEN - 1, "0");
        copy(eventData[ER_ATTACKER_STEAM64], MAX_STEAM64_LEN - 1, "0");
    }

    if (IsTrackablePlayer(victim))
    {
        GetPlayerNameSafe(victim, eventData[ER_VICTIM_NAME], MAX_NAME_LEN - 1);
        GetPlayerAuthSafe(victim, authNorm, charsmax(authNorm));
        copy(eventData[ER_VICTIM_AUTH], MAX_AUTH_LEN - 1, authNorm);
        FillSteam64Maybe(authNorm, steam64, charsmax(steam64));
        copy(eventData[ER_VICTIM_STEAM64], MAX_STEAM64_LEN - 1, steam64);
    }
    else
    {
        eventData[ER_VICTIM_NAME][0] = 0;
        copy(eventData[ER_VICTIM_AUTH], MAX_AUTH_LEN - 1, "0");
        copy(eventData[ER_VICTIM_STEAM64], MAX_STEAM64_LEN - 1, "0");
    }

    if (weapon[0]) copy(eventData[ER_WEAPON], MAX_WEAPON_LEN - 1, weapon);
    else eventData[ER_WEAPON][0] = 0;

    ArrayPushArray(g_Events, eventData);
    g_RoundEventCount++;
}

AddNamedEvent(const eventType[], const attackerName[], const attackerAuth[], const attackerSteam64[], const victimName[], const victimAuth[], const victimSteam64[], const weapon[], bool:headshot, Float:distance)
{
    new eventData[EventRec];

    eventData[ER_TIME] = get_systime();
    eventData[ER_HEADSHOT] = headshot ? 1 : 0;
    eventData[ER_DISTANCE100] = floatround(distance * 100.0);

    copy(eventData[ER_TYPE], MAX_TYPE_LEN - 1, eventType);
    copy(eventData[ER_ATTACKER_NAME], MAX_NAME_LEN - 1, attackerName);
    copy(eventData[ER_ATTACKER_AUTH], MAX_AUTH_LEN - 1, attackerAuth);
    copy(eventData[ER_ATTACKER_STEAM64], MAX_STEAM64_LEN - 1, attackerSteam64);
    copy(eventData[ER_VICTIM_NAME], MAX_NAME_LEN - 1, victimName);
    copy(eventData[ER_VICTIM_AUTH], MAX_AUTH_LEN - 1, victimAuth);
    copy(eventData[ER_VICTIM_STEAM64], MAX_STEAM64_LEN - 1, victimSteam64);
    copy(eventData[ER_WEAPON], MAX_WEAPON_LEN - 1, weapon);

    ArrayPushArray(g_Events, eventData);
    g_RoundEventCount++;
}

AddDeathEvent(killer, victim, const weapon[], headshot)
{
    new eventData[EventRec];
    new authNorm[MAX_AUTH_LEN], steam64[MAX_STEAM64_LEN];

    eventData[ER_TIME] = get_systime();
    eventData[ER_HEADSHOT] = headshot ? 1 : 0;
    eventData[ER_DISTANCE100] = 0;

    copy(eventData[ER_TYPE], MAX_TYPE_LEN - 1, "player_death");
    copy(eventData[ER_WEAPON], MAX_WEAPON_LEN - 1, weapon);

    if (IsTrackablePlayer(killer))
    {
        GetPlayerNameSafe(killer, eventData[ER_ATTACKER_NAME], MAX_NAME_LEN - 1);
        GetPlayerAuthSafe(killer, authNorm, charsmax(authNorm));
        copy(eventData[ER_ATTACKER_AUTH], MAX_AUTH_LEN - 1, authNorm);
        FillSteam64Maybe(authNorm, steam64, charsmax(steam64));
        copy(eventData[ER_ATTACKER_STEAM64], MAX_STEAM64_LEN - 1, steam64);
    }
    else
    {
        eventData[ER_ATTACKER_NAME][0] = 0;
        copy(eventData[ER_ATTACKER_AUTH], MAX_AUTH_LEN - 1, "0");
        copy(eventData[ER_ATTACKER_STEAM64], MAX_STEAM64_LEN - 1, "0");
    }

    if (IsTrackablePlayer(victim))
    {
        GetPlayerNameSafe(victim, eventData[ER_VICTIM_NAME], MAX_NAME_LEN - 1);
        GetPlayerAuthSafe(victim, authNorm, charsmax(authNorm));
        copy(eventData[ER_VICTIM_AUTH], MAX_AUTH_LEN - 1, authNorm);
        FillSteam64Maybe(authNorm, steam64, charsmax(steam64));
        copy(eventData[ER_VICTIM_STEAM64], MAX_STEAM64_LEN - 1, steam64);
    }
    else
    {
        eventData[ER_VICTIM_NAME][0] = 0;
        copy(eventData[ER_VICTIM_AUTH], MAX_AUTH_LEN - 1, "0");
        copy(eventData[ER_VICTIM_STEAM64], MAX_STEAM64_LEN - 1, "0");
    }

    if (IsTrackablePlayer(killer) && IsTrackablePlayer(victim))
    {
        eventData[ER_DISTANCE100] = floatround(GetPlayersDistance(killer, victim) * 100.0);
    }

    ArrayPushArray(g_Events, eventData);
    g_RoundEventCount++;
}

Float:GetPlayersDistance(id1, id2)
{
    new Float:origin1[3], Float:origin2[3];
    pev(id1, pev_origin, origin1);
    pev(id2, pev_origin, origin2);

    new Float:dx = origin1[0] - origin2[0];
    new Float:dy = origin1[1] - origin2[1];
    new Float:dz = origin1[2] - origin2[2];

    return floatsqroot(dx * dx + dy * dy + dz * dz);
}

UpdateLiveTimeOnDeath(id)
{
    if (!IsTrackablePlayer(id) || g_PlayerRoundDead[id])
        return;

    if (g_PlayerRoundSpawnTime[id] > 0)
    {
        g_PlayerRoundLiveTime[id] += (get_systime() - g_PlayerRoundSpawnTime[id]);
    }

    g_PlayerRoundDead[id] = true;
}

bool:IsTrackablePlayer(id)
{
    return (1 <= id <= MAX_PLAYERS && is_user_connected(id) && !is_user_hltv(id));
}

FindPlayerByAuthOrName(const authid[], const name[])
{
    new authRaw[MAX_AUTH_LEN], authNorm[MAX_AUTH_LEN], pname[MAX_NAME_LEN];

    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (!IsTrackablePlayer(id))
            continue;

        get_user_authid(id, authRaw, charsmax(authRaw));
        NormalizeSteamId(authRaw, authNorm, charsmax(authNorm));
        if (authid[0] && equal(authNorm, authid))
        {
            return id;
        }
    }

    for (new id = 1; id <= MAX_PLAYERS; id++)
    {
        if (!IsTrackablePlayer(id))
            continue;

        get_user_name(id, pname, charsmax(pname));
        if (name[0] && equal(pname, name))
        {
            return id;
        }
    }

    return 0;
}

GetPlayerNameSafe(id, output[], len)
{
    if (!IsTrackablePlayer(id))
    {
        output[0] = 0;
        return;
    }

    get_user_name(id, output, len);
}

GetPlayerNameRaw(id, output[], len)
{
    if (!(1 <= id <= MAX_PLAYERS))
    {
        output[0] = 0;
        return;
    }

    get_user_name(id, output, len);
}

GetPlayerAuthSafe(id, output[], len)
{
    if (!IsTrackablePlayer(id))
    {
        copy(output, len, "0");
        return;
    }

    new raw[MAX_AUTH_LEN];
    get_user_authid(id, raw, charsmax(raw));
    NormalizeSteamId(raw, output, len);
}

GetPlayerAuthRaw(id, output[], len)
{
    if (!(1 <= id <= MAX_PLAYERS))
    {
        copy(output, len, "0");
        return;
    }

    get_user_authid(id, output, len);
    if (!output[0])
    {
        copy(output, len, "0");
    }
}

GetPlayerTeamSafe(id, output[], len)
{
    if (!IsTrackablePlayer(id))
    {
        copy(output, len, "UNK");
        return;
    }

    switch (cs_get_user_team(id))
    {
        case CS_TEAM_T: copy(output, len, "T");
        case CS_TEAM_CT: copy(output, len, "CT");
        case CS_TEAM_SPECTATOR: copy(output, len, "SPEC");
        default: copy(output, len, "UNK");
    }
}

NormalizeSteamId(const input[], output[], len)
{
    if (!input[0]
    || equal(input, "BOT")
    || contain(input, "BOT") != -1
    || contain(input, "LAN") != -1
    || contain(input, "PENDING") != -1
    || equal(input, "HLTV"))
    {
        copy(output, len, "0");
        return;
    }

    if (contain(input, "STEAM_") == 0)
    {
        new parts[3][24];
        if (explode_colon(input, parts, sizeof(parts), sizeof(parts[])) >= 3)
        {
            format(output, len, "STEAM_0:%s:%s", parts[1], parts[2]);
            return;
        }
    }

    copy(output, len, input);
}

FillSteam64Maybe(const authid[], output[], len)
{
    if (get_pcvar_num(g_pcvar_include_steam64) == 0)
    {
        copy(output, len, "0");
        return;
    }

    SteamIdTo64(authid, output, len);
}

SteamIdTo64(const authid[], output[], len)
{
    new norm[MAX_AUTH_LEN];
    NormalizeSteamId(authid, norm, charsmax(norm));

    if (!norm[0] || equal(norm, "0") || contain(norm, "STEAM_") != 0)
    {
        copy(output, len, "0");
        return;
    }

    new parts[3][24];
    if (explode_colon(norm, parts, sizeof(parts), sizeof(parts[])) < 3)
    {
        copy(output, len, "0");
        return;
    }

    new doubled[32], account[32];
    MultiplyDecimalStringBy2(parts[2], doubled, charsmax(doubled));
    AddDecimalStrings(doubled, parts[1], account, charsmax(account));
    AddDecimalStrings("76561197960265728", account, output, len);
}

explode_colon(const input[], output[][], maxParts, maxLen)
{
    new inputLen = strlen(input);
    new part = 0, pos = 0;

    for (new i = 0; i <= inputLen; i++)
    {
        if (input[i] == ':' || input[i] == 0)
        {
            output[part][pos] = 0;
            part++;
            pos = 0;

            if (part >= maxParts)
                break;
        }
        else if (pos < maxLen - 1)
        {
            output[part][pos++] = input[i];
        }
    }

    return part;
}

MultiplyDecimalStringBy2(const input[], output[], len)
{
    new rev[64], idx = 0, carry = 0, digit, value;
    new inputLen = strlen(input);

    for (new i = inputLen - 1; i >= 0; i--)
    {
        digit = input[i] - '0';
        if (digit < 0 || digit > 9)
        {
            copy(output, len, "0");
            return;
        }

        value = digit * 2 + carry;
        rev[idx++] = (value % 10) + '0';
        carry = value / 10;
    }

    while (carry > 0)
    {
        rev[idx++] = (carry % 10) + '0';
        carry /= 10;
    }

    new outIdx = 0;
    for (new i = idx - 1; i >= 0 && outIdx < len - 1; i--)
    {
        output[outIdx++] = rev[i];
    }
    output[outIdx] = 0;
}

AddDecimalStrings(const a[], const b[], output[], len)
{
    new la = strlen(a), lb = strlen(b);
    new ia = la - 1, ib = lb - 1;
    new carry = 0;
    new rev[64], idx = 0;
    new da, db, sum;

    while (ia >= 0 || ib >= 0 || carry > 0)
    {
        if (ia >= 0) da = a[ia] - '0';
        else da = 0;

        if (ib >= 0) db = b[ib] - '0';
        else db = 0;

        sum = da + db + carry;
        rev[idx++] = (sum % 10) + '0';
        carry = sum / 10;

        ia--;
        ib--;
    }

    new outIdx = 0;
    for (new i = idx - 1; i >= 0 && outIdx < len - 1; i--)
    {
        output[outIdx++] = rev[i];
    }
    output[outIdx] = 0;
}

ResolveExportDir(output[], len)
{
    get_pcvar_string(g_pcvar_export_dir, output, len);
    trim(output);

    if (!output[0] || !dir_exists(output))
    {
        get_datadir(output, len);
    }
}

BuildTempRoundsPath()
{
    new exportDir[MAX_PATH_LEN], mapname[64];
    ResolveExportDir(exportDir, charsmax(exportDir));
    get_mapname(mapname, charsmax(mapname));

    format(g_TempRoundsPath, charsmax(g_TempRoundsPath), "%s/match_%s.rounds.tmp", exportDir, g_MatchUid);
}

BuildFinalExportPath(output[], len)
{
    new exportDir[MAX_PATH_LEN], mapname[64];
    ResolveExportDir(exportDir, charsmax(exportDir));
    get_mapname(mapname, charsmax(mapname));

    format(output, len, "%s/match_%s.json", exportDir, g_MatchUid);
}

BuildIndexPath()
{
    new exportDir[MAX_PATH_LEN];
    ResolveExportDir(exportDir, charsmax(exportDir));
    format(g_IndexPath, charsmax(g_IndexPath), "%s/match_json_exports.idx", exportDir);
}

AppendExportIndex(const exportPath[], timestamp)
{
    if (!exportPath[0])
        return;

    if (!g_IndexPath[0])
    {
        BuildIndexPath();
    }

    new line[MAX_PATH_LEN + 32];
    format(line, charsmax(line), "%d %s", timestamp, exportPath);
    write_file(g_IndexPath, line, -1);
}

CleanupOldExports()
{
    new retentionDays = get_pcvar_num(g_pcvar_json_retention_days);
    if (retentionDays <= 0)
        return;

    if (!g_IndexPath[0])
    {
        BuildIndexPath();
    }

    if (!file_exists(g_IndexPath))
        return;

    new now = get_systime();
    new expireSeconds = retentionDays * 86400;

    new txtLen = 0, lineNo = 0;
    new line[512], tsStr[32], path[MAX_PATH_LEN];
    new kept[256][MAX_PATH_LEN + 32];
    new keptCount = 0;

    while ((lineNo = read_file(g_IndexPath, lineNo, line, charsmax(line), txtLen)) != 0)
    {
        trim(line);
        if (!line[0])
            continue;

        tsStr[0] = 0;
        path[0] = 0;
        parse(line, tsStr, charsmax(tsStr), path, charsmax(path));

        if (!tsStr[0] || !path[0])
            continue;

        new ts = str_to_num(tsStr);
        if (ts > 0 && (now - ts) >= expireSeconds)
        {
            if (file_exists(path))
            {
                delete_file(path);
            }
            continue;
        }

        if (keptCount < sizeof(kept))
        {
            copy(kept[keptCount], charsmax(kept[]), line);
            keptCount++;
        }
    }

    delete_file(g_IndexPath);

    for (new i = 0; i < keptCount; i++)
    {
        write_file(g_IndexPath, kept[i], -1);
    }
}

AppendCurrentRoundToTemp(currentCT, currentT, const winner[], const reason[])
{
    new file = fopen(g_TempRoundsPath, "at");
    if (!file)
    {
        log_amx("[matchjson] failed to open temp file: %s", g_TempRoundsPath);
        return;
    }

    if (g_CompletedRounds > 0)
    {
        fprintf(file, ",^n");
    }

    fprintf(file, "    {^n");
    WriteCurrentEvents(file);
    WriteCurrentChats(file);
    WriteCurrentPlayers(file);
    fprintf(file, "      ^"round_num^": %d,^n", g_CompletedRounds + 1);
    fprintf(file, "      ^"time^": %d,^n", get_systime());
    fprintf(file, "      ^"warmup^": false,^n");
    fprintf(file, "      ^"winner^": ^"%s^",^n", winner);
    fprintf(file, "      ^"reason^": ^"%s^",^n", reason);
    fprintf(file, "      ^"ct_score^": %d,^n", currentCT);
    fprintf(file, "      ^"t_score^": %d^n", currentT);
    fprintf(file, "    }");

    fclose(file);
}

WriteCurrentEvents(file)
{
    fprintf(file, "      ^"events^": [^n");

    new count = ArraySize(g_Events);
    new eventData[EventRec];
    new bool:first = true;

    for (new i = 0; i < count; i++)
    {
        ArrayGetArray(g_Events, i, eventData);

        if (!first)
        {
            fprintf(file, ",^n");
        }

        new attackerName[MAX_JSON_BUF], attackerAuth[MAX_JSON_BUF], attackerSteam64[MAX_JSON_BUF];
        new victimName[MAX_JSON_BUF], victimAuth[MAX_JSON_BUF], victimSteam64[MAX_JSON_BUF];
        new weapon[MAX_JSON_BUF], evtype[MAX_JSON_BUF];

        JsonEscape(eventData[ER_ATTACKER_NAME], attackerName, charsmax(attackerName));
        JsonEscape(eventData[ER_ATTACKER_AUTH], attackerAuth, charsmax(attackerAuth));
        JsonEscape(eventData[ER_ATTACKER_STEAM64], attackerSteam64, charsmax(attackerSteam64));
        JsonEscape(eventData[ER_VICTIM_NAME], victimName, charsmax(victimName));
        JsonEscape(eventData[ER_VICTIM_AUTH], victimAuth, charsmax(victimAuth));
        JsonEscape(eventData[ER_VICTIM_STEAM64], victimSteam64, charsmax(victimSteam64));
        JsonEscape(eventData[ER_WEAPON], weapon, charsmax(weapon));
        JsonEscape(eventData[ER_TYPE], evtype, charsmax(evtype));

        fprintf(file, "        {^n");
        fprintf(file, "          ^"data^": {^n");
        fprintf(file, "            ^"assister^": {^"name^": ^"^", ^"steamid^": ^"0^", ^"steamid64^": ^"0^"},^n");
        fprintf(file, "            ^"attacker^": {^"name^": ^"%s^", ^"steamid^": ^"%s^", ^"steamid64^": ^"%s^"},^n", attackerName, attackerAuth, attackerSteam64);
        fprintf(file, "            ^"attackerblinded^": false,^n");
        fprintf(file, "            ^"distance^": %.2f,^n", eventData[ER_DISTANCE100] / 100.0);
        fprintf(file, "            ^"dominated^": 0,^n");
        if (eventData[ER_HEADSHOT]) fprintf(file, "            ^"headshot^": true,^n");
        else fprintf(file, "            ^"headshot^": false,^n");
        fprintf(file, "            ^"noscope^": false,^n");
        fprintf(file, "            ^"penetrated^": 0,^n");
        fprintf(file, "            ^"revenge^": 0,^n");
        fprintf(file, "            ^"throughsmoke^": false,^n");
        fprintf(file, "            ^"victim^": {^"name^": ^"%s^", ^"steamid^": ^"%s^", ^"steamid64^": ^"%s^"},^n", victimName, victimAuth, victimSteam64);
        fprintf(file, "            ^"weapon^": ^"%s^",^n", weapon);
        fprintf(file, "            ^"wipe^": 0^n");
        fprintf(file, "          },^n");
        fprintf(file, "          ^"event^": ^"%s^",^n", evtype);
        fprintf(file, "          ^"time^": %d^n", eventData[ER_TIME]);
        fprintf(file, "        }");

        first = false;
    }

    if (!first)
    {
        fprintf(file, "^n");
    }

    fprintf(file, "      ],^n");
}

WriteCurrentChats(file)
{
    new count = ArraySize(g_Chats);
    if (count <= 0)
    {
        return;
    }

    fprintf(file, "      ^"chat^": [^n");

    new chatData[ChatRec];
    for (new i = 0; i < count; i++)
    {
        ArrayGetArray(g_Chats, i, chatData);

        new nameEsc[MAX_JSON_BUF], authEsc[MAX_JSON_BUF], steam64Esc[MAX_JSON_BUF], msgEsc[384];
        JsonEscape(chatData[CR_NAME], nameEsc, charsmax(nameEsc));
        JsonEscape(chatData[CR_AUTH], authEsc, charsmax(authEsc));
        JsonEscape(chatData[CR_STEAM64], steam64Esc, charsmax(steam64Esc));
        JsonEscape(chatData[CR_MSG], msgEsc, charsmax(msgEsc));

        fprintf(file, "        {^"message^": ^"%s^", ^"name^": ^"%s^", ^"steamid^": ^"%s^", ^"steamid64^": ^"%s^", ^"time^": %d}", msgEsc, nameEsc, authEsc, steam64Esc, chatData[CR_TIME]);

        if (i < count - 1)
        {
            fprintf(file, ",^n");
        }
        else
        {
            fprintf(file, "^n");
        }
    }

    fprintf(file, "      ],^n");
}

WriteCurrentPlayers(file)
{
    fprintf(file, "      ^"players^": [^n");

    new count = ArraySize(g_PlayerRounds);
    new playerData[PlayerRoundRec];

    for (new i = 0; i < count; i++)
    {
        ArrayGetArray(g_PlayerRounds, i, playerData);

        new nameEsc[MAX_JSON_BUF], authEsc[MAX_JSON_BUF], steam64Esc[MAX_JSON_BUF], teamEsc[64];
        JsonEscape(playerData[PR_NAME], nameEsc, charsmax(nameEsc));
        JsonEscape(playerData[PR_AUTH], authEsc, charsmax(authEsc));
        JsonEscape(playerData[PR_STEAM64], steam64Esc, charsmax(steam64Esc));
        JsonEscape(playerData[PR_TEAM], teamEsc, charsmax(teamEsc));

        fprintf(file, "        {^n");
        fprintf(file, "          ^"data^": {^n");
        fprintf(file, "            ^"assists^": %d,^n", playerData[PR_ASSISTS]);
        fprintf(file, "            ^"cash_earned^": %d,^n", playerData[PR_CASH_EARNED]);
        fprintf(file, "            ^"damage^": %d,^n", playerData[PR_DAMAGE]);
        fprintf(file, "            ^"deaths^": %d,^n", playerData[PR_DEATHS]);
        fprintf(file, "            ^"enemies_flashed^": %d,^n", playerData[PR_ENEMIES_FLASHED]);
        fprintf(file, "            ^"equipment_value^": %d,^n", playerData[PR_EQUIP_VALUE]);
        fprintf(file, "            ^"headshot_kills^": %d,^n", playerData[PR_HEADSHOT_KILLS]);
        fprintf(file, "            ^"kill_reward^": %d,^n", playerData[PR_KILL_REWARD]);
        fprintf(file, "            ^"kills^": %d,^n", playerData[PR_KILLS]);
        fprintf(file, "            ^"live_time^": %d,^n", playerData[PR_LIVE_TIME]);
        fprintf(file, "            ^"money_saved^": %d,^n", playerData[PR_MONEY_SAVED]);
        fprintf(file, "            ^"plants^": %d,^n", playerData[PR_PLANTS]);
        fprintf(file, "            ^"defuses^": %d,^n", playerData[PR_DEFUSES]);
        fprintf(file, "            ^"explodes^": %d,^n", playerData[PR_EXPLODES]);
        fprintf(file, "            ^"objective^": %d,^n", playerData[PR_OBJECTIVE]);
        fprintf(file, "            ^"utility_damage^": %d^n", playerData[PR_UTILITY_DAMAGE]);
        fprintf(file, "          },^n");
        fprintf(file, "          ^"name^": ^"%s^",^n", nameEsc);
        fprintf(file, "          ^"steamid^": ^"%s^",^n", authEsc);
        fprintf(file, "          ^"steamid64^": ^"%s^",^n", steam64Esc);
        fprintf(file, "          ^"team^": ^"%s^"^n", teamEsc);
        fprintf(file, "        }");

        if (i < count - 1)
        {
            fprintf(file, ",^n");
        }
        else
        {
            fprintf(file, "^n");
        }
    }

    fprintf(file, "      ],^n");
}

ExportMatchJson(bool:isFinal)
{
    if (!g_MatchStarted)
        return;

    g_MatchEndTime = get_systime();

    BuildFinalExportPath(g_LastExportPath, charsmax(g_LastExportPath));

    new file = fopen(g_LastExportPath, "wt");
    if (!file)
    {
        log_amx("[matchjson] failed to open export: %s", g_LastExportPath);
        return;
    }

    new mapname[64], hostname[128], demoFilename[128], demoPath[192], demoProvider[64];
    new mapEsc[128], hostEsc[192], demoFileEsc[192], demoPathEsc[256], demoProvEsc[128];

    get_mapname(mapname, charsmax(mapname));
    get_cvar_string("hostname", hostname, charsmax(hostname));
    get_pcvar_string(g_pcvar_demo_filename, demoFilename, charsmax(demoFilename));
    get_pcvar_string(g_pcvar_demo_path, demoPath, charsmax(demoPath));
    get_pcvar_string(g_pcvar_demo_provider, demoProvider, charsmax(demoProvider));

    JsonEscape(mapname, mapEsc, charsmax(mapEsc));
    JsonEscape(hostname, hostEsc, charsmax(hostEsc));
    JsonEscape(demoFilename, demoFileEsc, charsmax(demoFileEsc));
    JsonEscape(demoPath, demoPathEsc, charsmax(demoPathEsc));
    JsonEscape(demoProvider, demoProvEsc, charsmax(demoProvEsc));

    copy(g_LastExportMatchId, charsmax(g_LastExportMatchId), g_MatchUid);

    fprintf(file, "{^n");
    fprintf(file, "  ^"schema_version^": ^"1.1^",^n");
    fprintf(file, "  ^"match_id^": ^"%s^",^n", g_MatchUid);
    fprintf(file, "  ^"match_unix_id^": %d,^n", g_MatchId);
    fprintf(file, "  ^"demo_uuid^": ^"%s^",^n", g_MatchUid);
    fprintf(file, "  ^"completed^": %s,^n", isFinal ? "true" : "false");
    fprintf(file, "  ^"export_type^": ^"%s^",^n", isFinal ? "final" : "snapshot");
    fprintf(file, "  ^"server_name^": ^"%s^",^n", hostEsc);
    fprintf(file, "  ^"demo_filename^": ^"%s^",^n", demoFileEsc);
    fprintf(file, "  ^"demo_path^": ^"%s^",^n", demoPathEsc);
    fprintf(file, "  ^"demo_provider^": ^"%s^",^n", demoProvEsc);
    fprintf(file, "  ^"demo^": {^n");
    fprintf(file, "    ^"provider^": ^"%s^",^n", demoProvEsc);
    fprintf(file, "    ^"filename^": ^"%s^",^n", demoFileEsc);
    fprintf(file, "    ^"path^": ^"%s^",^n", demoPathEsc);
    fprintf(file, "    ^"available^": %s^n", demoPath[0] ? "true" : "false");
    fprintf(file, "  },^n");
    fprintf(file, "  ^"start_time^": %d,^n", g_MatchStartTime);
    fprintf(file, "  ^"end_time^": %d,^n", g_MatchEndTime);
    fprintf(file, "  ^"map^": ^"%s^",^n", mapEsc);
    fprintf(file, "  ^"ct_score^": %d,^n", g_CTScore);
    fprintf(file, "  ^"t_score^": %d,^n", g_TScore);
    fprintf(file, "  ^"rounds^": [^n");

    if (file_exists(g_TempRoundsPath))
    {
        new lineIndex = 0, txtLen = 0, buffer[512];
        while ((lineIndex = read_file(g_TempRoundsPath, lineIndex, buffer, charsmax(buffer), txtLen)) != 0)
        {
            fprintf(file, "%s^n", buffer);
        }
    }

    fprintf(file, "  ]^n");
    fprintf(file, "}^n");

    fclose(file);

    AppendExportIndex(g_LastExportPath, g_MatchStartTime);
    CleanupOldExports();

    log_amx("[matchjson] exported: %s", g_LastExportPath);
}


CleanupMatchFiles()
{
    if (g_TempRoundsPath[0] && file_exists(g_TempRoundsPath))
    {
        delete_file(g_TempRoundsPath);
    }
}

SendExportedJsonToApi(const jsonPath[])
{
    if (get_pcvar_num(g_pcvar_api_enabled) == 0)
        return;

    if (!jsonPath[0] || !file_exists(jsonPath))
    {
        log_amx("[matchjson] api send skipped, file not found: %s", jsonPath);
        return;
    }

    new url[256];
    get_pcvar_string(g_pcvar_api_url, url, charsmax(url));
    trim(url);

    if (!url[0])
    {
        log_amx("[matchjson] api send skipped, mjl_api_url is empty");
        return;
    }

    new jsonBytes = file_size(jsonPath, FSOPT_BYTES_COUNT);
    if (jsonBytes <= 0)
    {
        log_amx("[matchjson] api send skipped, invalid json size for: %s", jsonPath);
        return;
    }

    if (jsonBytes >= sizeof(g_ApiBody))
    {
        log_amx("[matchjson] api send skipped, json too large (%d bytes, safe limit %d): %s", jsonBytes, sizeof(g_ApiBody) - 1, jsonPath);
        return;
    }

    arrayset(g_ApiBody, 0, sizeof(g_ApiBody));
    new bodyLen = LoadFileForMe(jsonPath, g_ApiBody, sizeof(g_ApiBody) - 1);
    if (bodyLen < 0)
    {
        log_amx("[matchjson] api send skipped, failed to load file: %s", jsonPath);
        return;
    }

    g_ApiBody[min(bodyLen, sizeof(g_ApiBody) - 1)] = 0;

    new EzHttpOptions:options_id = ezhttp_create_options();
    new timeout = get_pcvar_num(g_pcvar_api_timeout);
    if (timeout > 0)
    {
        ezhttp_option_set_connect_timeout(options_id, _:float(timeout));
        ezhttp_option_set_timeout(options_id, _:float(timeout));
    }

    ezhttp_option_set_queue(options_id, g_ApiQueue);
    ezhttp_option_set_plugin_end_behaviour(options_id, EZH_FORGET_REQUEST);
    ezhttp_option_set_header(options_id, "Content-Type", "application/json");

    new apiKey[256];
    get_pcvar_string(g_pcvar_api_key, apiKey, charsmax(apiKey));
    trim(apiKey);
    if (apiKey[0])
    {
        ezhttp_option_set_header(options_id, "X-API-Key", apiKey);
    }

    if (!g_LastExportMatchId[0])
    {
        copy(g_LastExportMatchId, charsmax(g_LastExportMatchId), g_MatchUid);
    }

    ezhttp_option_set_header(options_id, "X-Match-Id", g_LastExportMatchId);
    ezhttp_option_set_body(options_id, g_ApiBody);

    new userData[MAX_MATCH_ID_LEN];
    copy(userData, charsmax(userData), g_LastExportMatchId);
    ezhttp_option_set_user_data(options_id, userData, sizeof(userData));

    ezhttp_post(url, "OnApiSendComplete", options_id);
}

public OnApiSendComplete(EzHttpRequest:request_id, const data[])
{
    new matchId[MAX_MATCH_ID_LEN];
    copy(matchId, charsmax(matchId), data);

    if (ezhttp_get_error_code(request_id) != EZH_OK)
    {
        new error[128];
        ezhttp_get_error_message(request_id, error, charsmax(error));
        log_amx("[matchjson] api send failed for match %s: %s", matchId, error);
        return;
    }

    new response[512];
    ezhttp_get_data(request_id, response, charsmax(response));
    log_amx("[matchjson] api send ok for match %s: %s", matchId, response);
}


BuildMatchUid()
{
    new mapname[64], mapSafe[64];
    new serverUid[64], serverSafe[64];

    get_mapname(mapname, charsmax(mapname));
    SanitizeToken(mapname, mapSafe, charsmax(mapSafe));

    get_pcvar_string(g_pcvar_server_uid, serverUid, charsmax(serverUid));
    trim(serverUid);

    if (!serverUid[0])
    {
        get_cvar_string("ip", serverUid, charsmax(serverUid));
    }

    if (!serverUid[0])
    {
        copy(serverUid, charsmax(serverUid), "server");
    }

    SanitizeToken(serverUid, serverSafe, charsmax(serverSafe));
    format(g_MatchUid, charsmax(g_MatchUid), "%d_%s_%s", g_MatchStartTime, mapSafe, serverSafe);
}

SanitizeToken(const input[], output[], len)
{
    new i, j, c;
    new bool:lastUnderscore = false;

    for (i = 0, j = 0; input[i] != 0 && j < len - 1; i++)
    {
        c = tolower(input[i]);

        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
        {
            output[j++] = c;
            lastUnderscore = false;
            continue;
        }

        if (!lastUnderscore && j > 0)
        {
            output[j++] = '_';
            lastUnderscore = true;
        }
    }

    if (j > 0 && output[j - 1] == '_')
    {
        j--;
    }

    if (j == 0)
    {
        copy(output, len, "unknown");
        return;
    }

    output[j] = 0;
}

JsonEscape(const input[], output[], len)
{
    new i, j, c;

    for (i = 0, j = 0; input[i] != 0 && j < len - 1; i++)
    {
        c = input[i];

        switch (c)
        {
            case 92, 34:
            {
                if (j < len - 2)
                {
                    output[j++] = 92;
                    output[j++] = c;
                }
            }
            case 10:
            {
                if (j < len - 2)
                {
                    output[j++] = 92;
                    output[j++] = 110;
                }
            }
            case 13:
            {
                if (j < len - 2)
                {
                    output[j++] = 92;
                    output[j++] = 114;
                }
            }
            case 9:
            {
                if (j < len - 2)
                {
                    output[j++] = 92;
                    output[j++] = 116;
                }
            }
            default:
            {
                output[j++] = c;
            }
        }
    }

    output[j] = 0;
}
