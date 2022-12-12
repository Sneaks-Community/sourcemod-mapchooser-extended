/**
 * vim: set ts=4 :
 * =============================================================================
 * Rock The Vote Extended
 * Creates a map vote when the required number of players have requested one.
 *
 * Rock The Vote Extended (C)2012-2013 Powerlord (Ross Bemrose)
 * SourceMod (C)2004-2007 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

#include <sourcemod>
#include <mapchooser>
#include <mapchooser_extended>
#include <nextmap>
#include <multicolors>

#pragma newdecls required

#pragma semicolon 1

#define MCE_VERSION "1.11.0"

public Plugin myinfo =
{
    name        = "Rock The Vote Extended",
    author      = "Powerlord and AlliedModders LLC",
    description = "Provides RTV Map Voting",
    version     = MCE_VERSION,
    url         = "https://forums.alliedmods.net/showthread.php?t=156974"
};

ConVar g_Cvar_Needed;
ConVar g_Cvar_MinPlayers;
ConVar g_Cvar_InitialDelay;
ConVar g_Cvar_Interval;
ConVar g_Cvar_ChangeTime;
ConVar g_Cvar_RTVPostVoteAction;
ConVar g_Cvar_DisplayName;
ConVar g_Cvar_ChatPrefix;

Handle g_OnRTVForward          = INVALID_HANDLE;
Handle g_OnRockedForward          = INVALID_HANDLE;

bool g_CanRTV                = false; // True if RTV loaded maps and is active.
bool g_RTVAllowed            = false; // True if RTV is available to players. Used to delay rtv votes.
int g_Voters                 = 0;     // Total voters connected. Doesn't include fake clients.
int g_Votes                  = 0;     // Total number of "say rtv" votes
int g_VotesNeeded            = 0;     // Necessary votes before map vote begins. (voters * percent_needed)
bool g_Voted[MAXPLAYERS + 1] = { false, ... };

bool g_InChange = false;

char g_szChatPrefix[128];

public void OnPluginStart() {
    LoadTranslations("common.phrases");
    LoadTranslations("rockthevote.phrases");
    LoadTranslations("basevotes.phrases");

    g_Cvar_Needed            = CreateConVar("sm_rtv_needed", "0.60", "Percentage of players needed to rockthevote (Def 60%)", 0, true, 0.05, true, 1.0);
    g_Cvar_MinPlayers        = CreateConVar("sm_rtv_minplayers", "0", "Number of players required before RTV will be enabled.", 0, true, 0.0, true, float(MAXPLAYERS));
    g_Cvar_InitialDelay      = CreateConVar("sm_rtv_initialdelay", "30.0", "Time (in seconds) before first RTV can be held", 0, true, 0.00);
    g_Cvar_Interval          = CreateConVar("sm_rtv_interval", "240.0", "Time (in seconds) after a failed RTV before another can be held", 0, true, 0.00);
    g_Cvar_ChangeTime        = CreateConVar("sm_rtv_changetime", "0", "When to change the map after a succesful RTV: 0 - Instant, 1 - RoundEnd, 2 - MapEnd", _, true, 0.0, true, 2.0);
    g_Cvar_RTVPostVoteAction = CreateConVar("sm_rtv_postvoteaction", "0", "What to do with RTV's after a mapvote has completed. 0 - Allow, success = instant change, 1 - Deny", _, true, 0.0, true, 1.0);
    g_Cvar_DisplayName       = CreateConVar("sm_rtv_displayname", "1", "Display the Map's custom name, instead of the raw map name", _, true, 0.0, true, 1.0);
    g_Cvar_ChatPrefix        = CreateConVar("sm_rtv_chatprefix", "[MCE] ", "Chat prefix for all RTV related messages");

    g_OnRTVForward = CreateGlobalForward("OnRockTheVote", ET_Ignore, Param_Cell);
    g_OnRockedForward = CreateGlobalForward("OnVoteRocked", ET_Ignore, Param_String);

    RegConsoleCmd("sm_rtv", Command_RTV);

    RegAdminCmd("sm_forcertv", Command_ForceRTV, ADMFLAG_CHANGEMAP, "Force an RTV vote");
    RegAdminCmd("mce_forcertv", Command_ForceRTV, ADMFLAG_CHANGEMAP, "Force an RTV vote");

    // Rock The Vote Extended cvars
    CreateConVar("rtve_version", MCE_VERSION, "Rock The Vote Extended Version", FCVAR_SPONLY | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    AutoExecConfig(true, "rtv");
}

public void OnMapStart() {
    g_Voters      = 0;
    g_Votes       = 0;
    g_VotesNeeded = 0;
    g_InChange    = false;

    /* Handle late load */
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientConnected(i)) {
            OnClientConnected(i);
        }
    }
}

public void OnMapEnd() {
    g_CanRTV      = false;
    g_RTVAllowed  = false;
    g_Voters      = 0;
    g_Votes       = 0;
    g_VotesNeeded = 0;
    g_InChange    = false;
}

public void OnConfigsExecuted() {
    g_CanRTV     = true;
    g_RTVAllowed = false;
    CreateTimer(g_Cvar_InitialDelay.FloatValue, Timer_DelayRTV, _, TIMER_FLAG_NO_MAPCHANGE);

    GetConVarString(g_Cvar_ChatPrefix, g_szChatPrefix, sizeof(g_szChatPrefix));
    HookConVarChange(g_Cvar_ChatPrefix, OnSettingsChanged);
}

public void OnSettingsChanged(Handle convar, const char[] oldValue, const char[] newValue) {
    if (convar == g_Cvar_ChatPrefix) {
        GetConVarString(g_Cvar_ChatPrefix, g_szChatPrefix, sizeof(g_szChatPrefix));
    }
}

public void OnClientConnected(int client) {
    if (IsFakeClient(client))
        return;

    g_Voted[client] = false;

    g_Voters++;
    g_VotesNeeded = RoundToCeil(float(g_Voters) * g_Cvar_Needed.FloatValue);

    return;
}

public void OnClientDisconnect(int client) {
    if (IsFakeClient(client))
        return;

    if (g_Voted[client]) {
        g_Votes--;
    }

    g_Voters--;

    g_VotesNeeded = RoundToCeil(float(g_Voters) * g_Cvar_Needed.FloatValue);

    if (!g_CanRTV) {
        return;
    }

    if (g_Votes && g_Voters && g_Votes >= g_VotesNeeded && g_RTVAllowed) {
        if (g_Cvar_RTVPostVoteAction.IntValue == 1 && HasEndOfMapVoteFinished()) {
            return;
        }

        StartRTV();
    }
}

public Action Command_RTV(int client, int args) {
    if (!g_CanRTV || !client) {
        return Plugin_Handled;
    }

    AttemptRTV(client);

    return Plugin_Handled;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs) {
    if (!g_CanRTV || !client || IsChatTrigger()) {
        return;
    }

    if (strcmp(sArgs, "rtv", false) == 0 || strcmp(sArgs, "rockthevote", false) == 0) {
        ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);

        AttemptRTV(client);

        SetCmdReplySource(old);
    }
}

void AttemptRTV(int client) {
    if (!g_RTVAllowed || (g_Cvar_RTVPostVoteAction.IntValue == 1 && HasEndOfMapVoteFinished())) {
        CReplyToCommand(client, "%s%t", g_szChatPrefix, "RTV Not Allowed");
        return;
    }

    if (!CanMapChooserStartVote()) {
        CReplyToCommand(client, "%s%t", g_szChatPrefix, "RTV Started");
        return;
    }

    if (GetClientCount(true) < g_Cvar_MinPlayers.IntValue) {
        CReplyToCommand(client, "%s%t", g_szChatPrefix, "Minimal Players Not Met");
        return;
    }

    if (g_Voted[client]) {
        CReplyToCommand(client, "%s%t", g_szChatPrefix, "Already Voted", g_Votes, g_VotesNeeded);
        return;
    }

    Call_StartForward(g_OnRTVForward);
    Call_PushCell(client);
    Call_Finish();

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));

    g_Votes++;
    g_Voted[client] = true;

    CPrintToChatAll("%s%t", g_szChatPrefix, "RTV Requested", name, g_Votes, g_VotesNeeded);

    if (g_Votes >= g_VotesNeeded) {
        StartRTV();
    }
}


public Action Timer_DelayRTV(Handle timer) {
    g_RTVAllowed = true;
}

void StartRTV() {
    if (g_InChange) {
        return;
    }

    if (EndOfMapVoteEnabled() && HasEndOfMapVoteFinished()) {
        /* Change right now then */
        char map[PLATFORM_MAX_PATH];
        if (GetNextMap(map, sizeof(map))) {
            Call_StartForward(g_OnRockedForward);
            Call_PushString(map);
            Call_Finish();
            if (GetConVarBool(g_Cvar_DisplayName)) {
                char mapName[PLATFORM_MAX_PATH];
                GetMapName(map, mapName, sizeof(mapName));
                CPrintToChatAll("%s%t", g_szChatPrefix, "Changing Maps", mapName);
            } else {
                CPrintToChatAll("%s%t", g_szChatPrefix, "Changing Maps", map);
            }
            CreateTimer(5.0, Timer_ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
            g_InChange = true;

            ResetRTV();

            g_RTVAllowed = false;
        }
        return;
    }

    if (CanMapChooserStartVote()) {
        MapChange when = view_as<MapChange>(g_Cvar_ChangeTime.IntValue);
        InitiateMapChooserVote(when);

        ResetRTV();

        g_RTVAllowed = false;
        CreateTimer(g_Cvar_Interval.FloatValue, Timer_DelayRTV, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

void ResetRTV() {
    g_Votes = 0;

    for (int i = 1; i <= MAXPLAYERS; i++) {
        g_Voted[i] = false;
    }
}

public Action Timer_ChangeMap(Handle hTimer) {
    g_InChange = false;

    LogMessage("RTV changing map manually");

    char map[PLATFORM_MAX_PATH];
    if (GetNextMap(map, sizeof(map))) {
        ForceChangeLevel(map, "RTV after mapvote");
    }

    return Plugin_Stop;
}

// Rock The Vote Extended functions
public Action Command_ForceRTV(int client, int args) {
    if (!g_CanRTV || !client) {
        return Plugin_Handled;
    }

    ShowActivity2(client, "%s", "%t", g_szChatPrefix, "Initiated Vote Map");

    StartRTV();

    return Plugin_Handled;
}
