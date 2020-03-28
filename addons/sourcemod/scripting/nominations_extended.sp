/**
 * vim: set ts=4 :
 * =============================================================================
 * Nominations Extended
 * Allows players to nominate maps for Mapchooser
 *
 * Nominations Extended (C)2012-2013 Powerlord (Ross Bemrose)
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
#include "include/mapchooser_extended"
#include <colors>
#pragma semicolon 1
#pragma newdecls required

#define MCE_VERSION "1.10.0"

public Plugin myinfo =
{
	name = "Map Nominations Extended",
	author = "Powerlord and AlliedModders LLC",
	description = "Provides Map Nominations",
	version = MCE_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=156974"
};

Handle g_Cvar_ExcludeOld = INVALID_HANDLE;
Handle g_Cvar_ExcludeCurrent = INVALID_HANDLE;
Handle g_Cvar_DisplayName = INVALID_HANDLE;

Handle g_MapList = INVALID_HANDLE;
Handle g_MapMenu = INVALID_HANDLE;
int g_mapFileSerial = -1;

#define MAPSTATUS_ENABLED (1<<0)
#define MAPSTATUS_DISABLED (1<<1)
#define MAPSTATUS_EXCLUDE_CURRENT (1<<2)
#define MAPSTATUS_EXCLUDE_PREVIOUS (1<<3)
#define MAPSTATUS_EXCLUDE_NOMINATED (1<<4)

Handle g_mapTrie;

// Nominations Extended Convars
Handle g_Cvar_MarkCustomMaps = INVALID_HANDLE;

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("nominations.phrases");
	LoadTranslations("basetriggers.phrases"); // for Next Map phrase
	LoadTranslations("mapchooser_extended.phrases");
	
	int arraySize = ByteCountToCells(PLATFORM_MAX_PATH);	
	g_MapList = CreateArray(arraySize);
	
	g_Cvar_ExcludeOld = CreateConVar("sm_nominate_excludeold", "1", "Specifies if the current map should be excluded from the Nominations list", 0, true, 0.00, true, 1.0);
	g_Cvar_ExcludeCurrent = CreateConVar("sm_nominate_excludecurrent", "1", "Specifies if the MapChooser excluded maps should also be excluded from Nominations", 0, true, 0.00, true, 1.0);
	g_Cvar_DisplayName = CreateConVar("sm_nominate_displayname", "1", "Use custom Display Names instead of the raw map name", 0, true, 0.00, true, 1.0);
	
	RegConsoleCmd("sm_nominate", Command_Nominate);
	
	RegAdminCmd("sm_nominate_addmap", Command_Addmap, ADMFLAG_CHANGEMAP, "sm_nominate_addmap <mapname> - Forces a map to be on the next mapvote.");
	
	// Nominations Extended cvars
	CreateConVar("ne_version", MCE_VERSION, "Nominations Extended Version", FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);


	g_mapTrie = CreateTrie();
}

public void OnAllPluginsLoaded()
{
	// This is an MCE cvar... this plugin requires MCE to be loaded.  Granted, this plugin SHOULD have an MCE dependency.
	g_Cvar_MarkCustomMaps = FindConVar("mce_markcustommaps");
}

public void OnConfigsExecuted()
{
	if (ReadMapList(g_MapList,
					g_mapFileSerial,
					"nominations",
					MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER)
		== INVALID_HANDLE)
	{
		if (g_mapFileSerial == -1)
		{
			SetFailState("Unable to create a valid map list.");
		}
	}
	
	BuildMapMenu();
}

public void OnNominationRemoved(const char[] map, int owner)
{
	int status;

	char resolvedMap[PLATFORM_MAX_PATH];
	FindMap(map, resolvedMap, sizeof(resolvedMap));

	/* Is the map in our list? */
	if (!GetTrieValue(g_mapTrie, map, status))
	{
		return;	
	}
	
	/* Was the map disabled due to being nominated */
	if ((status & MAPSTATUS_EXCLUDE_NOMINATED) != MAPSTATUS_EXCLUDE_NOMINATED)
	{
		return;
	}
	
	SetTrieValue(g_mapTrie, map, MAPSTATUS_ENABLED);	
}

stock void getMapName(const char[] map, char[] mapName, int size)
{
	if (GetConVarBool(g_Cvar_DisplayName))
	{
		GetMapName(map, mapName, size);
		return;
	}
	strcopy(mapName, size, map);
}

public Action Command_Addmap(int client, int args)
{
	if (args < 1)
	{
		CReplyToCommand(client, "[SNK.SRV] Usage: sm_nominate_addmap <mapname>");
		return Plugin_Handled;
	}
	
	char mapname[PLATFORM_MAX_PATH];
	char resolvedMap[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));

	if (FindMap(mapname, resolvedMap, sizeof(resolvedMap)) == FindMap_NotFound)
	{
		// We couldn't resolve the map entry to a filename, so...
		ReplyToCommand(client, "%t", "Map was not found", mapname);
		return Plugin_Handled;		
	}

	char mapName[PLATFORM_MAX_PATH];
	getMapName(mapname, mapName, sizeof(mapName));
	
	int status;
	if (!GetTrieValue(g_mapTrie, mapname, status))
	{
		CReplyToCommand(client, "%t", "Map was not found", mapName);
		return Plugin_Handled;		
	}
	
	NominateResult result = NominateMap(mapname, true, 0);
	
	if (result > Nominate_Replaced)
	{
		/* We assume already in vote is the casue because the maplist does a Map Validity check and we forced, so it can't be full */
		CReplyToCommand(client, "%t", "Map Already In Vote", mapName);
		
		return Plugin_Handled;	
	}

	SetTrieValue(g_mapTrie, mapname, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

	CReplyToCommand(client, "%t", "Map Inserted", mapName);
	LogAction(client, -1, "\"%L\" inserted map \"%s\".", client, mapname);

	return Plugin_Handled;		
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (!client)
	{
		return;
	}
	
	if (strcmp(sArgs, "nominate", false) == 0)
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
		
		AttemptNominate(client);
		
		SetCmdReplySource(old);
	}
}

public Action Command_Nominate(int client, int args)
{
	if (!client || !IsNominateAllowed(client))
	{
		return Plugin_Handled;
	}
	
	if (args == 0)
	{
		AttemptNominate(client);
		return Plugin_Handled;
	}
	
	char mapname[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));

	if (FindMap(mapname, mapname, sizeof(mapname)) == FindMap_NotFound)
	{
		// We couldn't resolve the map entry to a filename, so...
		ReplyToCommand(client, "%t", "Map was not found", mapname);
		return Plugin_Handled;		
	}

	char displayName[PLATFORM_MAX_PATH];
	GetMapDisplayName(mapname, displayName, sizeof(displayName));

	int status;
	if (!GetTrieValue(g_mapTrie, mapname, status))
	{
		CReplyToCommand(client, "%t", "Map was not found", mapname);
		return Plugin_Handled;		
	}
	
	if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
	{
		if ((status & MAPSTATUS_EXCLUDE_CURRENT) == MAPSTATUS_EXCLUDE_CURRENT)
		{
			CReplyToCommand(client, "[SNK.SRV] %t", "Can't Nominate Current Map");
		}
		
		if ((status & MAPSTATUS_EXCLUDE_PREVIOUS) == MAPSTATUS_EXCLUDE_PREVIOUS)
		{
			CReplyToCommand(client, "[SNK.SRV] %t", "Map in Exclude List");
		}
		
		if ((status & MAPSTATUS_EXCLUDE_NOMINATED) == MAPSTATUS_EXCLUDE_NOMINATED)
		{
			CReplyToCommand(client, "[SNK.SRV] %t", "Map Already Nominated");
		}
		
		return Plugin_Handled;
	}
	
	NominateResult result = NominateMap(mapname, false, client);
	
	if (result > Nominate_Replaced)
	{
		if (result == Nominate_AlreadyInVote)
		{
			CReplyToCommand(client, "%t", "Map Already In Vote", mapname);
		}
		else
		{
			CReplyToCommand(client, "[SNK.SRV] %t", "Map Already Nominated");
		}
		
		return Plugin_Handled;	
	}
	
	/* Map was nominated! - Disable the menu item and update the trie */
	
	SetTrieValue(g_mapTrie, mapname, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);
	
	char mapName[PLATFORM_MAX_PATH];
	getMapName(mapname, mapName, sizeof(mapName));
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	PrintToChatAll("[SNK.SRV] %t", "Map Nominated", name, mapName);
	LogMessage("%s nominated %s", name, mapname);

	return Plugin_Continue;
}

void AttemptNominate(int client)
{
	SetMenuTitle(g_MapMenu, "%T", "Nominate Title", client);
	DisplayMenu(g_MapMenu, client, MENU_TIME_FOREVER);
	
	return;
}

void BuildMapMenu()
{
	delete g_MapMenu;
	
	ClearTrie(g_mapTrie);
	
	g_MapMenu = new Menu(Handler_MapSelectMenu, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);

	char map[PLATFORM_MAX_PATH];
	
	Handle excludeMaps = INVALID_HANDLE;
	char currentMap[PLATFORM_MAX_PATH];
	
	if (GetConVarBool(g_Cvar_ExcludeOld))
	{	
		excludeMaps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
		GetExcludeMapList(excludeMaps);
	}
	
	if (GetConVarBool(g_Cvar_ExcludeCurrent))
	{
		GetCurrentMap(currentMap, sizeof(currentMap));
	}
	
	bool DisplayName = GetConVarBool(g_Cvar_DisplayName);
	for (int i = 0; i < GetArraySize(g_MapList); i++)
	{
		int status = MAPSTATUS_ENABLED;
		
		GetArrayString(g_MapList, i, map, sizeof(map));

		FindMap(map, map, sizeof(map));

		char displayName[PLATFORM_MAX_PATH];
		GetMapDisplayName(map, displayName, sizeof(displayName));

		if (GetConVarBool(g_Cvar_ExcludeCurrent))
		{
			if (StrEqual(map, currentMap))
			{
				status = MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_CURRENT;
			}
		}
		
		/* Dont bother with this check if the current map check passed */
		if (GetConVarBool(g_Cvar_ExcludeOld) && status == MAPSTATUS_ENABLED)
		{
			if (FindStringInArray(excludeMaps, map) != -1)
			{
				status = MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_PREVIOUS;
			}
		}
		
		if (DisplayName)
		{
			char mapName[PLATFORM_MAX_PATH];
			GetMapName(map, mapName, sizeof(mapName));
			AddMenuItem(g_MapMenu, map, mapName);
		}
		else
		{
			AddMenuItem(g_MapMenu, map, map);
		}
		SetTrieValue(g_mapTrie, map, status);
	}
	
	SetMenuExitButton(g_MapMenu, true);

	delete excludeMaps;
}

public int Handler_MapSelectMenu(Handle menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char map[PLATFORM_MAX_PATH], name[MAX_NAME_LENGTH];
			GetMenuItem(menu, param2, map, sizeof(map));		
			
			char mapName[PLATFORM_MAX_PATH];
			getMapName(map, mapName, sizeof(mapName));
			
			GetClientName(param1, name, MAX_NAME_LENGTH);
	
			NominateResult result = NominateMap(map, false, param1);
			
			/* Don't need to check for InvalidMap because the menu did that already */
			if (result == Nominate_AlreadyInVote)
			{
				PrintToChat(param1, "[SNK.SRV] %t", "Map Already Nominated");
				return 0;
			}
			else if (result == Nominate_VoteFull)
			{
				PrintToChat(param1, "[SNK.SRV] %t", "Max Nominations");
				return 0;
			}
			
			SetTrieValue(g_mapTrie, map, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

			if (result == Nominate_Replaced)
			{
				PrintToChatAll("[SNK.SRV] %t", "Map Nomination Changed", name, mapName);
				return 0;	
			}
			
			PrintToChatAll("[SNK.SRV] %t", "Map Nominated", name, mapName);
			LogMessage("%s nominated %s", name, map);
		}
		
		case MenuAction_DrawItem:
		{
			char map[PLATFORM_MAX_PATH];
			GetMenuItem(menu, param2, map, sizeof(map));
			
			int status;
			
			if (!GetTrieValue(g_mapTrie, map, status))
			{
				LogError("Menu selection of item not in trie. Major logic problem somewhere.");
				return ITEMDRAW_DEFAULT;
			}
			
			if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
			{
				return ITEMDRAW_DISABLED;	
			}
			
			return ITEMDRAW_DEFAULT;
						
		}
		
		case MenuAction_DisplayItem:
		{
			char map[PLATFORM_MAX_PATH];
			GetMenuItem(menu, param2, map, sizeof(map));
			
			int mark = GetConVarInt(g_Cvar_MarkCustomMaps);
			bool official;

			int status;
			
			if (!GetTrieValue(g_mapTrie, map, status))
			{
				LogError("Menu selection of item not in trie. Major logic problem somewhere.");
				return 0;
			}
			
			char buffer[100];
			char display[150];
			
			if (mark)
			{
				official = IsMapOfficial(map);
			}
			
			if (mark && !official)
			{
				switch (mark)
				{
					case 1:
					{
						Format(buffer, sizeof(buffer), "%T", "Custom Marked", param1, map);
					}
					
					case 2:
					{
						Format(buffer, sizeof(buffer), "%T", "Custom", param1, map);
					}
				}
			}
			else
			{
				getMapName(map, buffer, sizeof(buffer));
			}
			
			if ((status & MAPSTATUS_DISABLED) == MAPSTATUS_DISABLED)
			{
				if ((status & MAPSTATUS_EXCLUDE_CURRENT) == MAPSTATUS_EXCLUDE_CURRENT)
				{
					Format(display, sizeof(display), "%s (%T)", buffer, "Current Map", param1);
					return RedrawMenuItem(display);
				}
				
				if ((status & MAPSTATUS_EXCLUDE_PREVIOUS) == MAPSTATUS_EXCLUDE_PREVIOUS)
				{
					Format(display, sizeof(display), "%s (%T)", buffer, "Recently Played", param1);
					return RedrawMenuItem(display);
				}
				
				if ((status & MAPSTATUS_EXCLUDE_NOMINATED) == MAPSTATUS_EXCLUDE_NOMINATED)
				{
					Format(display, sizeof(display), "%s (%T)", buffer, "Nominated", param1);
					return RedrawMenuItem(display);
				}
			}
			
			if (mark && !official)
				return RedrawMenuItem(buffer);
			
			return 0;
		}
	}
	
	return 0;
}

stock bool IsNominateAllowed(int client)
{
	CanNominateResult result = CanNominate();
	
	switch(result)
	{
		case CanNominate_No_VoteInProgress:
		{
			CReplyToCommand(client, "[SNK.SRV] %t", "Nextmap Voting Started");
			return false;
		}
		
		case CanNominate_No_VoteComplete:
		{
			char map[PLATFORM_MAX_PATH];
			GetNextMap(map, sizeof(map));
			CReplyToCommand(client, "[SNK.SRV] %t", "Next Map", map);
			return false;
		}
		
		case CanNominate_No_VoteFull:
		{
			CReplyToCommand(client, "[SNK.SRV] %t", "Max Nominations");
			return false;
		}
	}
	
	return true;
}