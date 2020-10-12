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
#undef REQUIRE_PLUGIN
#tryinclude <shavit>
#tryinclude <kztimer>
#tryinclude <surftimer>
#pragma semicolon 1
#pragma newdecls required

#define MCE_VERSION "1.10.0"

public Plugin myinfo =
{
	name = "Map Nominations Extended",
	author = "Powerlord and AlliedModders LLC", // mbhound version ( ͡° ͜ʖ ͡°)
	description = "Provides Map Nominations",
	version = MCE_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=156974"
};

Handle g_Cvar_ExcludeOld = INVALID_HANDLE;
Handle g_Cvar_ExcludeCurrent = INVALID_HANDLE;
Handle g_Cvar_DisplayName = INVALID_HANDLE;
Handle g_Cvar_EnhancedMenu = INVALID_HANDLE;

ConVar g_Cvar_MinTier;
ConVar g_Cvar_MaxTier;
ConVar g_Cvar_ChatPrefix;

Handle g_MapList = INVALID_HANDLE;
Handle g_MapMenu = INVALID_HANDLE;
int g_mapFileSerial = -1;

Menu g_EnhancedMenu;
ArrayList g_aTierMenus;

char g_szChatPrefix[128];

bool g_bBhopTimer = false;
bool g_bKzTimer = false;
bool g_bSurfTimer = false;

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
	g_aTierMenus = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	g_Cvar_ExcludeOld = CreateConVar("sm_nominate_excludeold", "1", "Specifies if the current map should be excluded from the Nominations list", 0, true, 0.00, true, 1.0);
	g_Cvar_ExcludeCurrent = CreateConVar("sm_nominate_excludecurrent", "1", "Specifies if the MapChooser excluded maps should also be excluded from Nominations", 0, true, 0.00, true, 1.0);
	g_Cvar_DisplayName = CreateConVar("sm_nominate_displayname", "1", "Use custom Display Names instead of the raw map name", 0, true, 0.00, true, 1.0);
	g_Cvar_EnhancedMenu = CreateConVar("sm_enhanced_menu", "1", "Nominate menu can show maps by alphabetic order and tiers", 0, true, 0.0, true, 1.0 );
	g_Cvar_MinTier = CreateConVar("sm_min_tier", "1", "The minimum tier to show on the enhanced menu",  _, true, 0.0, true, 10.0);
	g_Cvar_MaxTier = CreateConVar("sm_max_tier", "6", "The maximum tier to show on the enhanced menu",  _, true, 0.0, true, 10.0);
	g_Cvar_ChatPrefix = CreateConVar("sm_nominate_chatprefix", "[SNK.SRV] ", "Chat prefix for all Nominations Extended related messages");

	RegConsoleCmd("sm_nominate", Command_Nominate);
	
	RegAdminCmd("sm_nominate_addmap", Command_Addmap, ADMFLAG_CHANGEMAP, "sm_nominate_addmap <mapname> - Forces a map to be on the next mapvote.");
	
	// Nominations Extended cvars
	CreateConVar("ne_version", MCE_VERSION, "Nominations Extended Version", FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	AutoExecConfig(true, "nominations_extended");

	g_mapTrie = CreateTrie();
}

public void OnAllPluginsLoaded()
{
	// This is an MCE cvar... this plugin requires MCE to be loaded.  Granted, this plugin SHOULD have an MCE dependency.
	g_Cvar_MarkCustomMaps = FindConVar("mce_markcustommaps");
}

public void OnLibraryAdded(const char[] szName)
{
	if (StrEqual(szName, "shavit"))
	{
		g_bBhopTimer = true;
	}
	if (StrEqual(szName, "KZTimer"))
	{
		g_bKzTimer = true;
	}
	if (StrEqual(szName, "surftimer"))
	{
		g_bSurfTimer = true;
	}
}

public void OnLibraryRemoved(const char[] szName)
{
	if (StrEqual(szName, "shavit"))
	{
		g_bBhopTimer = false;
	}
	if (StrEqual(szName, "KZTimer"))
	{
		g_bKzTimer = false;
	}
	if (StrEqual(szName, "surftimer"))
	{
		g_bSurfTimer = false;
	}
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

	if (GetConVarBool(g_Cvar_EnhancedMenu))
	{
		BuildTierMenus();
	}
	
	GetConVarString(g_Cvar_ChatPrefix, g_szChatPrefix, sizeof(g_szChatPrefix));
	HookConVarChange(g_Cvar_ChatPrefix, OnSettingsChanged);
}

public void OnSettingsChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_Cvar_ChatPrefix)
	{
		GetConVarString(g_Cvar_ChatPrefix, g_szChatPrefix, sizeof(g_szChatPrefix));
	}
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
		if (GetConVarBool(g_Cvar_EnhancedMenu)) 
		{
			OpenTiersMenu(client);
		}
		else
		{
			AttemptNominate(client);
		}
		return Plugin_Handled;
	}
	
	char mapname[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));

	ShowMatches(client, mapname);

	return Plugin_Continue;
}

void ShowMatches(int client, char[] mapname) 
{
	Menu SubMapMenu = new Menu(Handler_MapSelectMenu, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);
	SetMenuTitle(SubMapMenu, "Nominate Menu\nMaps matching \"%s\"\n ", mapname);
	SetMenuExitButton(SubMapMenu, true);

	bool isCurrent = false;
	bool isExclude = false;

	char map[PLATFORM_MAX_PATH];
	char lastMap[PLATFORM_MAX_PATH];

	Handle excludeMaps = INVALID_HANDLE;
	char currentMap[32];
	
	excludeMaps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
	GetExcludeMapList(excludeMaps);

	GetCurrentMap(currentMap, sizeof(currentMap));	

	for (int i = 0; i < GetArraySize(g_MapList); i++)
	{	
		GetArrayString(g_MapList, i, map, sizeof(map));

		if(StrContains(map, mapname, false) != -1)
		{
			if (GetConVarBool(g_Cvar_ExcludeCurrent) && StrEqual(map, currentMap))
			{
				isCurrent = true;
				continue;
			}

			if (GetConVarBool(g_Cvar_ExcludeOld) && FindStringInArray(excludeMaps, map) != -1)
			{
				isExclude = true;
				continue;
			}

			if (GetConVarBool(g_Cvar_DisplayName))
			{
				char mapName[PLATFORM_MAX_PATH];
				GetMapName(map, mapName, sizeof(mapName));
				AddMenuItem(SubMapMenu, map, mapName);
			}
			else
			{
				AddMenuItem(SubMapMenu, map, map);
			}
			strcopy(lastMap, sizeof(map), map);
		}
	}

	delete excludeMaps;

	switch (GetMenuItemCount(SubMapMenu)) 
	{
    	case 0:
    	{
			if (isCurrent) 
			{
				CReplyToCommand(client, "%s%t", g_szChatPrefix, "Can't Nominate Current Map");
			}
			else if (isExclude)
			{
				CReplyToCommand(client, "%s%t", g_szChatPrefix, "Map in Exclude List");
			}
			else 
			{
				CReplyToCommand(client, "%s%t", g_szChatPrefix, "Map was not found", mapname);
			}

			delete SubMapMenu;
    	}
   		case 1:
   		{
			NominateResult result = NominateMap(lastMap, false, client);
	
			if (result > Nominate_Replaced)
			{
				if (result == Nominate_AlreadyInVote)
				{
					CReplyToCommand(client, "%s%t", g_szChatPrefix, "Map Already In Vote", lastMap);
				}
				else
				{
					CReplyToCommand(client, "%s%t", g_szChatPrefix, "Map Already Nominated");
				}
			}
			else 
			{
				SetTrieValue(g_mapTrie, lastMap, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

				char name[MAX_NAME_LENGTH];
				GetClientName(client, name, sizeof(name));
				PrintToChatAll("%s%t", g_szChatPrefix, "Map Nominated", name, lastMap);
				LogMessage("\"%L\" nominated %s", client, lastMap);
			}	


			delete SubMapMenu;
   		}
   		default: 
   		{
			DisplayMenu(SubMapMenu, client, MENU_TIME_FOREVER);   		
		}
  	}
}

void AttemptNominate(int client)
{
	SetMenuTitle(g_MapMenu, "%T", "Nominate Title", client);
	DisplayMenu(g_MapMenu, client, MENU_TIME_FOREVER);
	
	return;
}

void OpenTiersMenu(int client)
{
	if (GetConVarBool(g_Cvar_EnhancedMenu))
	{
		DisplayMenu(g_EnhancedMenu, client, MENU_TIME_FOREVER);
	}

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

	if(GetConVarBool(g_Cvar_EnhancedMenu)) 
	{
		SetMenuExitBackButton(g_MapMenu, true);
	}

	delete excludeMaps;
}

void BuildEnhancedMenu()
{
	delete g_EnhancedMenu;

	g_EnhancedMenu = new Menu(TiersMenuHandler);
	g_EnhancedMenu.ExitButton = true;
	
	g_EnhancedMenu.SetTitle("Nominate Menu");	
	g_EnhancedMenu.AddItem("Alphabetic", "Alphabetic");

	int min = GetConVarInt(g_Cvar_MinTier);
	int max = GetConVarInt(g_Cvar_MaxTier);

	for( int i = min; i <= max; ++i )
	{
		if (GetMenuItemCount(g_aTierMenus.Get(i-min)) > 0) 
		{
			char tierDisplay[PLATFORM_MAX_PATH + 32];
			Format(tierDisplay, sizeof(tierDisplay), "Tier %i", i);

			char tierString[PLATFORM_MAX_PATH + 32];
			Format(tierString, sizeof(tierString), "%i", i);
			g_EnhancedMenu.AddItem(tierString, tierDisplay);
		}
	}
}

void BuildTierMenus() 
{
	int min = GetConVarInt(g_Cvar_MinTier);
	int max = GetConVarInt(g_Cvar_MaxTier);

	if (max < min)
	{
		int temp = max;
		max = min;
		min = temp;
		SetConVarInt(g_Cvar_MinTier, min);
		SetConVarInt(g_Cvar_MaxTier, max);
	}

	InitTierMenus(min,max);

	char map[PLATFORM_MAX_PATH];
	
	bool DisplayName = GetConVarBool(g_Cvar_DisplayName);
	for (int i = 0; i < GetArraySize(g_MapList); i++)
	{		
		GetArrayString(g_MapList, i, map, sizeof(map));

		FindMap(map, map, sizeof(map));

		char displayName[PLATFORM_MAX_PATH];
		GetMapDisplayName(map, displayName, sizeof(displayName));

		int tier = GetTier(map);
		
		if (DisplayName)
		{
			char mapName[PLATFORM_MAX_PATH];
			GetMapName(map, mapName, sizeof(mapName));
			AddMapToTierMenu(tier, map, mapName);
		}
		else
		{
			AddMapToTierMenu(tier, map, map);
		}
	}

	BuildEnhancedMenu();
}

void InitTierMenus(int min, int max) 
{
	g_aTierMenus.Clear();

	for(int i = min; i <= max; i++)
	{
		Menu TierMenu = new Menu(Handler_MapSelectMenu, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);
		TierMenu.SetTitle("Nominate Menu\nTier \"%i\" Maps\n ", i);
		TierMenu.ExitBackButton = true;

		g_aTierMenus.Push(TierMenu);
	}
}

void AddMapToTierMenu(int tier, char[] map, char[] mapName)
{
	if (GetConVarInt(g_Cvar_MinTier) <= tier <= GetConVarInt(g_Cvar_MaxTier))
	{
		AddMenuItem(g_aTierMenus.Get(tier-GetConVarInt(g_Cvar_MinTier)), map, mapName);	
	}
}

public int Handler_MapSelectMenu(Menu menu, MenuAction action, int param1, int param2)
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
				PrintToChat(param1, "%s%t", g_szChatPrefix, "Map Already Nominated");
				return 0;
			}
			else if (result == Nominate_VoteFull)
			{
				PrintToChat(param1, "%s%t", g_szChatPrefix, "Max Nominations");
				return 0;
			}
			
			SetTrieValue(g_mapTrie, map, MAPSTATUS_DISABLED|MAPSTATUS_EXCLUDE_NOMINATED);

			if (result == Nominate_Replaced)
			{
				PrintToChatAll("%s%t", g_szChatPrefix, "Map Nomination Changed", name, mapName);
				return 0;	
			}
			
			PrintToChatAll("%s%t", g_szChatPrefix, "Map Nominated", name, mapName);
			LogMessage("\"%L\" nominated %s", param1, map);
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

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				if (GetConVarBool(g_Cvar_EnhancedMenu))
				{
					OpenTiersMenu(param1);
				}
			}
		}
	}

	if (action == MenuAction_End) 
	{
		if (menu != g_MapMenu && FindValueInArray(g_aTierMenus, menu) == -1)
		{
			delete menu;
		}
	}
	
	return 0;
}

public int TiersMenuHandler(Menu menu, MenuAction action, int client, int param2) 
{
	if (action == MenuAction_Select) 
	{
		char option[PLATFORM_MAX_PATH];
		menu.GetItem(param2, option, sizeof(option));

		if (StrEqual(option , "Alphabetic")) 
		{
			AttemptNominate(client);
		}
		else 
		{
			DisplayMenu(g_aTierMenus.Get(StringToInt(option)-GetConVarInt(g_Cvar_MinTier)), client, MENU_TIME_FOREVER);
		}
	}
}

stock bool IsNominateAllowed(int client)
{
	CanNominateResult result = CanNominate();
	
	switch(result)
	{
		case CanNominate_No_VoteInProgress:
		{
			CReplyToCommand(client, "%s%t", g_szChatPrefix, "Nextmap Voting Started");
			return false;
		}
		
		case CanNominate_No_VoteComplete:
		{
			char map[PLATFORM_MAX_PATH];
			GetNextMap(map, sizeof(map));
			CReplyToCommand(client, "%s%t", g_szChatPrefix, "Next Map", map);
			return false;
		}
		
		case CanNominate_No_VoteFull:
		{
			CReplyToCommand(client, "%s%t", g_szChatPrefix, "Max Nominations");
			return false;
		}
	}
	
	return true;
}

int GetTier(char[] mapname)
{
	int tier = 0;
	if (g_bBhopTimer) 
	{
		char mapdisplay[PLATFORM_MAX_PATH + 32];
		GetMapDisplayName(mapname, mapdisplay, sizeof(mapdisplay));
		tier = Shavit_GetMapTier(mapdisplay);
	}
	else if (!g_bKzTimer)
	{

	}
	else if (!g_bSurfTimer)
	{

	}
	else if (GetConVarBool(g_Cvar_DisplayName))
	{
		char mapDisplay[PLATFORM_MAX_PATH];
		GetMapName(mapname, mapDisplay, sizeof(mapDisplay));

		int length = strlen(mapDisplay);
		tier = -1;
		for (int i = length - 1; i >= 0; i-- )
		{
			char c = mapDisplay[i];
			if (c < '0' || c > '9')
			{ 
				continue;
			}
			else
			{
				tier = (c - '0');
				if (i > 0)
				{
					char d = mapDisplay[i-1];
					if (d < '0' || d > '9')
					{
						break;
					}
					else 
					{
						tier = (d - '0') * 10 + tier; 
					}
				}
				break;
			}
		}
	}



	if (tier < GetConVarInt(g_Cvar_MinTier)) 
	{
		tier = GetConVarInt(g_Cvar_MinTier);
	}
	else if (tier > GetConVarInt(g_Cvar_MaxTier))
	{
		tier = GetConVarInt(g_Cvar_MaxTier);
	}

	return tier;
}
