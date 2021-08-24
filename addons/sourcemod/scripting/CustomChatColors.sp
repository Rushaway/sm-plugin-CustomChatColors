#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>
#include <multicolors>
//#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <ccc>

#define PLUGIN_VERSION					"7.0"

#define DATABASE_NAME					"ccc"

#define MAX_CHAT_TRIGGER_LENGTH			32
#define MAX_CHAT_LENGTH					192

#define REPLACE_LIST_MAX_LENGTH			255

public Plugin myinfo =
{
	name        = "Custom Chat Colors & Tags & Allchat",
	author      = "Dr. McKay, edit by id/Obus, BotoX, maxime1907",
	description = "Processes chat and provides colors & custom tags & allchat & chat ignoring",
	version     = PLUGIN_VERSION,
	url         = "http://www.doctormckay.com"
};

//Handle colorForward;
//Handle nameForward;
//Handle tagForward;
//Handle applicationForward;
//Handle messageForward;
Handle preLoadedForward;
Handle loadedForward;
Handle configReloadedForward;

ConVar g_cvar_GreenText;
ConVar g_cvar_ReplaceText;

ConVar g_cvar_SQLRetryTime;
ConVar g_cvar_SQLMaxRetries;

ConVar g_cSmCategoryColor;
ConVar g_cSmNameColor;
ConVar g_cSmChatColor;

char g_sSmCategoryColor[32];
char g_sSmNameColor[32];
char g_sSmChatColor[32];

//Handle g_hAdminMenu = null;

char g_sReplaceList[REPLACE_LIST_MAX_LENGTH][2][MAX_CHAT_LENGTH];
int g_iReplaceListSize = 0;

char g_sClientSID[MAXPLAYERS + 1][32];

int g_iClientEnable[MAXPLAYERS + 1] = { 1, ...};
char g_sClientTag[MAXPLAYERS + 1][64];
char g_sClientTagColor[MAXPLAYERS + 1][32];
char g_sClientNameColor[MAXPLAYERS + 1][32];
char g_sClientChatColor[MAXPLAYERS + 1][32];

int g_iDefaultClientEnable[MAXPLAYERS + 1] = { 1, ... };
char g_sDefaultClientTag[MAXPLAYERS + 1][32];
char g_sDefaultClientTagColor[MAXPLAYERS + 1][12];
char g_sDefaultClientNameColor[MAXPLAYERS + 1][12];
char g_sDefaultClientChatColor[MAXPLAYERS + 1][12];

ArrayList g_sColorsArray = null;

int g_iClientBanned[MAXPLAYERS + 1] = { -1, ...};
bool g_bWaitingForChatInput[MAXPLAYERS + 1];
char g_sReceivedChatInput[MAXPLAYERS + 1][64];
char g_sInputType[MAXPLAYERS + 1][32];
char g_sATargetSID[MAXPLAYERS + 1][64];
int g_iATarget[MAXPLAYERS + 1];

Handle g_hDatabase = null;

int g_msgAuthor;
bool g_msgIsChat;
char g_msgName[128];
char g_msgSender[128];
char g_msgText[MAX_CHAT_LENGTH];
char g_msgFinal[255];
bool g_msgIsTeammate;

bool g_Ignored[(MAXPLAYERS + 1) * (MAXPLAYERS + 1)] = {false, ...};

int g_bSQLSelectReplaceRetry = 0;
int g_bSQLInsertReplaceRetry[MAXPLAYERS + 1] = { 0, ... };
int g_bSQLDeleteReplaceRetry[MAXPLAYERS + 1] = { 0, ... };

int g_bSQLSelectBanRetry[MAXPLAYERS + 1] = { 0, ... };
int g_bSQLInsertBanRetry[MAXPLAYERS + 1] = { 0, ... };
int g_bSQLDeleteBanRetry[MAXPLAYERS + 1] = { 0, ... };

int g_bSQLSelectTagGroupRetry[MAXPLAYERS + 1] = { 0, ... };
int g_bSQLSelectTagRetry[MAXPLAYERS + 1] = { 0, ... };
int g_bSQLUpdateTagRetry[MAXPLAYERS + 1] = { 0, ... };
int g_bSQLInsertTagRetry[MAXPLAYERS + 1] = { 0, ... };
int g_bSQLDeleteTagRetry[MAXPLAYERS + 1] = { 0, ... };

bool g_bSQLite = true;
bool g_bLate = false;

bool g_bProto;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Updater_AddPlugin");

	CreateNative("CCC_UnLoadClient", Native_UnLoadClient);
	CreateNative("CCC_LoadClient", Native_LoadClient);
	CreateNative("CCC_ReloadConfig", Native_ReloadConfig);

	CreateNative("CCC_GetColor", Native_GetColor);
	CreateNative("CCC_SetColor", Native_SetColor);
	CreateNative("CCC_GetTag", Native_GetTag);
	CreateNative("CCC_SetTag", Native_SetTag);
	CreateNative("CCC_ResetColor", Native_ResetColor);
	CreateNative("CCC_ResetTag", Native_ResetTag);

	CreateNative("CCC_UpdateIgnoredArray", Native_UpdateIgnoredArray);

	RegPluginLibrary("ccc");

	g_bLate = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("allchat.phrases");

	//new Handle g_hTemporary = null;
	//if(LibraryExists("adminmenu") && ((g_hTemporary = GetAdminTopMenu()) != null))
	//{
	//	OnAdminMenuReady(g_hTemporary);
	//}

	UserMsg SayText2 = GetUserMessageId("SayText2");

	if (SayText2 == INVALID_MESSAGE_ID)
	{
		SetFailState("This game doesn't support SayText2 user messages.");
	}

	HookUserMessage(SayText2, Hook_UserMessage, true);
	HookEvent("player_say", Event_PlayerSay);

	RegAdminCmd("sm_cccimportreplacefile", Command_CCCImportReplaceFile, ADMFLAG_CONFIG, "Import a chat replace config from file");
	RegAdminCmd("sm_cccaddtag", Command_CCCAddTag, ADMFLAG_CONFIG, "Adds a tag entry");
	RegAdminCmd("sm_cccdeletetag", Command_CCCDeleteTag, ADMFLAG_CONFIG, "Deletes a tag entry");
	RegAdminCmd("sm_cccaddtrigger", Command_CCCAddTrigger, ADMFLAG_CONFIG, "Adds a chat trigger (Example: \":lenny:\"");
	RegAdminCmd("sm_cccdeletetrigger", Command_CCCDeleteTrigger, ADMFLAG_CONFIG, "Deletes a chat trigger (Example: \":lenny:\"");
	RegAdminCmd("sm_reloadccc", Command_ReloadConfig, ADMFLAG_CONFIG, "Reloads Custom Chat Colors config file");
	RegAdminCmd("sm_forcetag", Command_ForceTag, ADMFLAG_CHEATS, "Forcefully changes a clients custom tag");
	RegAdminCmd("sm_forcetagcolor", Command_ForceTagColor, ADMFLAG_CHEATS, "Forcefully changes a clients custom tag color");
	RegAdminCmd("sm_forcenamecolor", Command_ForceNameColor, ADMFLAG_CHEATS, "Forcefully changes a clients name color");
	RegAdminCmd("sm_forcetextcolor", Command_ForceTextColor, ADMFLAG_CHEATS, "Forcefully changes a clients chat text color");
	RegAdminCmd("sm_cccreset", Command_CCCReset, ADMFLAG_SLAY, "Resets a users custom tag, tag color, name color and chat text color");
	RegAdminCmd("sm_cccban", Command_CCCBan, ADMFLAG_SLAY, "Bans a user from changing his custom tag, tag color, name color and chat text color");
	RegAdminCmd("sm_cccunban", Command_CCCUnban, ADMFLAG_SLAY, "Unbans a user and allows for change of his tag, tag color, name color and chat text color");
	RegAdminCmd("sm_tagmenu", Command_TagMenu, ADMFLAG_CUSTOM1, "Shows the main \"tag & colors\" menu");
	RegAdminCmd("sm_tag", Command_SetTag, ADMFLAG_CUSTOM1, "Changes your custom tag");
	RegAdminCmd("sm_tags", Command_TagMenu, ADMFLAG_CUSTOM1, "Shows the main \"tag & colors\" menu");
	RegAdminCmd("sm_cleartag", Command_ClearTag, ADMFLAG_CUSTOM1, "Clears your custom tag");
	RegAdminCmd("sm_tagcolor", Command_SetTagColor, ADMFLAG_CUSTOM1, "Changes the color of your custom tag");
	RegAdminCmd("sm_cleartagcolor", Command_ClearTagColor, ADMFLAG_CUSTOM1, "Clears the color from your custom tag");
	RegAdminCmd("sm_namecolor", Command_SetNameColor, ADMFLAG_CUSTOM1, "Changes the color of your name");
	RegAdminCmd("sm_clearnamecolor", Command_ClearNameColor, ADMFLAG_CUSTOM1, "Clears the color from your name");
	RegAdminCmd("sm_textcolor", Command_SetTextColor, ADMFLAG_CUSTOM1, "Changes the color of your chat text");
	RegAdminCmd("sm_chatcolor", Command_SetTextColor, ADMFLAG_CUSTOM1, "Changes the color of your chat text");
	RegAdminCmd("sm_cleartextcolor", Command_ClearTextColor, ADMFLAG_CUSTOM1, "Clears the color from your chat text");
	RegAdminCmd("sm_clearchatcolor", Command_ClearTextColor, ADMFLAG_CUSTOM1, "Clears the color from your chat text");
	RegAdminCmd("sm_toggletag", Command_ToggleTag, ADMFLAG_CUSTOM1, "Toggles whether or not your tag and colors show in the chat");

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");

	// Override base chat
	AddCommandListener(Command_SmSay, "sm_say");
	AddCommandListener(Command_SmPSay, "sm_psay");
	AddCommandListener(Command_SmChat, "sm_chat");

	g_cvar_GreenText = CreateConVar("sm_ccc_green_text", "1", "Enables greentexting (First chat character must be \">\")", FCVAR_REPLICATED);
	g_cvar_ReplaceText = CreateConVar("sm_ccc_replace", "1", "Enables text replacing", FCVAR_REPLICATED);

	g_cvar_SQLRetryTime = CreateConVar("sm_ccc_sql_retry_time", "10.0", "Number of seconds to wait before a new retry on a failed query", FCVAR_REPLICATED);
	g_cvar_SQLMaxRetries = CreateConVar("sm_ccc_sql_max_retries", "1", "Number of sql retries on all queries if one fails", FCVAR_REPLICATED);

	g_cSmCategoryColor = CreateConVar("sm_ccc_sm_category_color", "{green}", "Color used for SM categories (ADMINS, ALL, Private to)", FCVAR_REPLICATED);
	g_cSmNameColor = CreateConVar("sm_ccc_sm_name_color", "{fullred}", "Color used for SM player name", FCVAR_REPLICATED);
	g_cSmChatColor = CreateConVar("sm_ccc_sm_chat_color", "{cyan}", "Color used for SM chat", FCVAR_REPLICATED);

	//colorForward = CreateGlobalForward("CCC_OnChatColor", ET_Event, Param_Cell);
	//nameForward = CreateGlobalForward("CCC_OnNameColor", ET_Event, Param_Cell);
	//tagForward = CreateGlobalForward("CCC_OnTagApplied", ET_Event, Param_Cell);
	//applicationForward = CreateGlobalForward("CCC_OnColor", ET_Event, Param_Cell, Param_String, Param_Cell);
	//messageForward = CreateGlobalForward("CCC_OnChatMessage", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	preLoadedForward = CreateGlobalForward("CCC_OnUserConfigPreLoaded", ET_Event, Param_Cell);
	loadedForward = CreateGlobalForward("CCC_OnUserConfigLoaded", ET_Ignore, Param_Cell);
	configReloadedForward = CreateGlobalForward("CCC_OnConfigReloaded", ET_Ignore);

	AutoExecConfig(true);

	ResetReplace();

	SQLInitialize();

	LoadColorArray();

	if (g_bLate)
		LateLoad();
}

public void OnPluginEnd()
{
	if (g_hDatabase != null)
		delete g_hDatabase;
	if (g_sColorsArray != null)
		delete g_sColorsArray;
}

public void OnConfigsExecuted()
{
	g_cSmCategoryColor.GetString(g_sSmCategoryColor, sizeof(g_sSmCategoryColor));
	g_cSmNameColor.GetString(g_sSmNameColor, sizeof(g_sSmNameColor));
	g_cSmChatColor.GetString(g_sSmChatColor, sizeof(g_sSmChatColor));
	g_bProto = CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf;
}

public void OnClientDisconnect(int client)
{
	// Check if the client has changed anything in its ccc config
	if (g_iDefaultClientEnable[client] == g_iClientEnable[client] &&
		StrEqual(g_sDefaultClientTag[client], g_sClientTag[client]) &&
		StrEqual(g_sDefaultClientTagColor[client], g_sClientTagColor[client]) &&
		StrEqual(g_sDefaultClientNameColor[client], g_sClientNameColor[client]) &&
		StrEqual(g_sDefaultClientChatColor[client], g_sClientChatColor[client]))
		return;

	// If we successfully selected the client previously
	if (g_sClientSID[client][0] != '\0')
		SQLUpdate_TagClient(INVALID_HANDLE, client);
	else
		SQLInsert_TagClient(INVALID_HANDLE, client);
}

public void OnClientPostAdminCheck(int client)
{
	ResetClient(client);

	if (HasFlag(client, Admin_Custom1))
	{
		SQLSelect_TagClient(INVALID_HANDLE, client);
		SQLSelect_Ban(INVALID_HANDLE, client);
	}
	else if (HasFlag(client, Admin_Generic))
	{
		char sClientSteamID[64];
		GetClientAuthId(client, AuthId_Steam2, sClientSteamID, sizeof(sClientSteamID));

		char sClientFlagString[64];
		GetClientFlagString(client, sClientFlagString, sizeof(sClientFlagString));

		DataPack pack = new DataPack();
		pack.WriteCell(client);
		pack.WriteString(sClientSteamID);
		pack.WriteString(sClientFlagString);

		SQLSelect_TagGroup(INVALID_HANDLE, pack);
	}
}

stock void LateLoad()
{
	ResetReplace();
	SQLSelect_Replace(INVALID_HANDLE);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		ResetClient(i);
		OnClientPostAdminCheck(i);
	}
}

stock void LoadColorArray()
{
	StringMap smTrie = MC_GetTrie();
	StringMapSnapshot smTrieSnapshot = smTrie.Snapshot();
	if (smTrie != null)
	{
		if (g_sColorsArray != null)
			delete g_sColorsArray;

		g_sColorsArray = new ArrayList(smTrie.Size);

		for (int i = 0; i < smTrie.Size; i++)
		{
			char key[64];

			smTrieSnapshot.GetKey(i, key, sizeof(key));

			g_sColorsArray.PushString(key);
		}
	}
	SortColors();
}

stock void SortColors()
{
	if (g_sColorsArray == null)
		return;

	char temp[64];

    // Sorting strings using bubble sort
	for (int j = 0; j < g_sColorsArray.Length - 1; j++)
	{
		for (int i = j + 1; i < g_sColorsArray.Length; i++)
		{
			char keyJ[64];
			char keyI[64];
			g_sColorsArray.GetString(j, keyJ, sizeof(keyJ));
			g_sColorsArray.GetString(i, keyI, sizeof(keyI));
			if (strcmp(keyJ, keyI) > 0)
			{
				Format(temp, sizeof(temp), "%s", keyJ);
				Format(keyJ, sizeof(keyJ), "%s", keyI);
				Format(keyI, sizeof(keyI), "%s", temp);
				g_sColorsArray.SetString(j, keyJ);
				g_sColorsArray.SetString(i, keyI);
			}
		}
	}
}

stock void ResetReplace()
{
	for (int i = 0; i < REPLACE_LIST_MAX_LENGTH; i++)
	{
		g_sReplaceList[i][0] = "";
		g_sReplaceList[i][1] = "";
	}
	g_iReplaceListSize = 0;
}

///////////
/// SQL ///
///////////

stock void SQLInitialize()
{
	if (g_hDatabase != null)
		delete g_hDatabase;

	if (SQL_CheckConfig(DATABASE_NAME))
		SQL_TConnect(OnSQLConnected, DATABASE_NAME);
	else
		SetFailState("Could not find \"%s\" entry in databases.cfg.", DATABASE_NAME);
}

stock void OnSQLConnected(Handle hParent, Handle hChild, const char[] err, any data)
{
	if (hChild == null)
	{
		LogError("Failed to connect to database \"%s\", retrying in %d seconds. (%s)", DATABASE_NAME, GetConVarFloat(g_cvar_SQLRetryTime), err);
		CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLReconnect);

		return;
	}

	char sDriver[16];
	g_hDatabase = CloneHandle(hChild);
	SQL_GetDriverIdent(hParent, sDriver, sizeof(sDriver));

	SQL_LockDatabase(g_hDatabase);

	if (!strncmp(sDriver, "my", 2, false))
		g_bSQLite = false;
	else
		g_bSQLite = true;

	SQLSetNames(INVALID_HANDLE);

	SQLTableCreation_Tag(INVALID_HANDLE);
	SQLTableCreation_Ban(INVALID_HANDLE);
	SQLTableCreation_Replace(INVALID_HANDLE);

	SQL_UnlockDatabase(g_hDatabase);
}

stock Action SQLReconnect(Handle hTimer)
{
	SQLInitialize();

	return Plugin_Stop;
}

stock Action SQLSetNames(Handle timer)
{
	if (!g_bSQLite)
		SQL_TQuery(g_hDatabase, OnSqlSetNames, "SET NAMES \"UTF8\"");
}

stock Action SQLTableCreation_Tag(Handle timer)
{
	if (g_bSQLite)
		SQL_TQuery(g_hDatabase, OnSQLTableCreated_Tag, "CREATE TABLE IF NOT EXISTS `ccc_tag` (`steamid` TEXT NOT NULL, `enable` INTEGER NOT NULL DEFAULT 1, `name` TEXT NOT NULL, `flag` VARCHAR(32), `tag` TEXT, `tag_color` TEXT, `name_color` TEXT, `chat_color` TEXT, PRIMARY KEY(`steamid`));");
	else
		SQL_TQuery(g_hDatabase, OnSQLTableCreated_Tag, "CREATE TABLE IF NOT EXISTS `ccc_tag` (`steamid` VARCHAR(32) NOT NULL, `enable` INT NOT NULL DEFAULT 1, `name` VARCHAR(32) NOT NULL, `flag` VARCHAR(32), `tag` VARCHAR(32), `tag_color` VARCHAR(6), `name_color` VARCHAR(6), `chat_color` VARCHAR(6), PRIMARY KEY(`steamid`)) CHARACTER SET utf8 COLLATE utf8_general_ci;");
	return Plugin_Stop;
}

stock Action SQLTableCreation_Ban(Handle timer)
{
	if (g_bSQLite)
		SQL_TQuery(g_hDatabase, OnSQLTableCreated_Ban, "CREATE TABLE IF NOT EXISTS `ccc_ban` (`steamid` TEXT NOT NULL, `name` TEXT NOT NULL, `issuer_steamid` TEXT NOT NULL, `issuer_name` TEXT NOT NULL, `length` INTEGER NOT NULL, PRIMARY KEY(`steamid`));");
	else
		SQL_TQuery(g_hDatabase, OnSQLTableCreated_Ban, "CREATE TABLE IF NOT EXISTS `ccc_ban` (`steamid` VARCHAR(32) NOT NULL, `name` VARCHAR(32) NOT NULL, `issuer_steamid` VARCHAR(32) NOT NULL, `issuer_name` VARCHAR(32) NOT NULL, `length` INT NOT NULL, PRIMARY KEY(`steamid`)) CHARACTER SET utf8 COLLATE utf8_general_ci;");
	return Plugin_Stop;
}

stock Action SQLTableCreation_Replace(Handle timer)
{
	if (g_bSQLite)
		SQL_TQuery(g_hDatabase, OnSQLTableCreated_Replace, "CREATE TABLE IF NOT EXISTS `ccc_replace` (`trigger` TEXT NOT NULL, `value` TEXT NOT NULL, PRIMARY KEY(`trigger`));");
	else
		SQL_TQuery(g_hDatabase, OnSQLTableCreated_Replace, "CREATE TABLE IF NOT EXISTS `ccc_replace` (`trigger` VARCHAR(32) NOT NULL, `value` VARCHAR(255) NOT NULL, PRIMARY KEY(`trigger`)) CHARACTER SET utf8 COLLATE utf8_general_ci;");
	return Plugin_Stop;
}

stock Action SQLSelect_Replace(Handle timer)
{
	if (g_hDatabase == null)
		return Plugin_Stop;

	char sQuery[256];

	Format(sQuery, sizeof(sQuery), "SELECT `trigger`, `value` FROM `ccc_replace`;");
	SQL_TQuery(g_hDatabase, OnSQLSelect_Replace, sQuery, 0, DBPrio_High);
	return Plugin_Stop;
}

stock Action SQLSelect_Ban(Handle timer, any client)
{
	if (g_hDatabase == null)
		return Plugin_Stop;

	char sQuery[256];
	char sClientSteamID[32];

	GetClientAuthId(client, AuthId_Steam2, sClientSteamID, sizeof(sClientSteamID));
	Format(sQuery, sizeof(sQuery), "SELECT `length` FROM `ccc_ban` WHERE `steamid` = '%s';", sClientSteamID);
	SQL_TQuery(g_hDatabase, OnSQLSelect_Ban, sQuery, client, DBPrio_High);
	return Plugin_Stop;
}

stock Action SQLSelect_TagGroup(Handle timer, any data)
{
	if (g_hDatabase == null)
		return Plugin_Stop;

	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char sFlagList[64];

	pack.ReadCell();
	pack.ReadString("", 0);
	pack.ReadString(sFlagList, sizeof(sFlagList));

	char sQuery[512];

	Format(sQuery, sizeof(sQuery), "SELECT `steamid`, `enable`, `tag`, `tag_color`, `name_color`, `chat_color`, `flag` FROM `ccc_tag` WHERE `steamid` NOT LIKE 'STEAM_%' and `flag` IS NOT NULL and `flag` != '' and `flag` IN (%s) ORDER BY `flag` DESC;", sFlagList);
	SQL_TQuery(g_hDatabase, OnSQLSelect_TagGroup, sQuery, data, DBPrio_High);
	return Plugin_Stop;
}

stock void GetClientFlagString(int client, char[] sClientFlagString, int maxSize)
{
	sClientFlagString[0] = '\0';

	AdminId aid = GetUserAdmin(client);

	AdminFlag admFlags[32];
	int iFlagsBits = GetAdminFlags(aid, Access_Real);
	iFlagsBits |= GetAdminFlags(aid, Access_Effective);
	int iAdmFlagsSize = FlagBitsToArray(iFlagsBits, admFlags, sizeof(admFlags));

	for (int i = 0; i < iAdmFlagsSize; i++)
	{
		int cFlag;
		if (FindFlagChar(admFlags[i], cFlag))
		{
			char sBuffer[64];
			Format(sBuffer, sizeof(sBuffer), "%s\"%c\",", sClientFlagString, cFlag);
			Format(sClientFlagString, maxSize, "%s", sBuffer);
		}
	}

	if (sClientFlagString[strlen(sClientFlagString) - 1] == ',')
		sClientFlagString[strlen(sClientFlagString) - 1] = '\0';

	if (sClientFlagString[0] == '\0')
	{
		sClientFlagString[0] = '\"';
		sClientFlagString[1] = '\"';
		sClientFlagString[2] = '\0';
	}
}

stock Action SQLSelect_TagClient(Handle timer, any client)
{
	char sClientSteamID[32];

	GetClientAuthId(client, AuthId_Steam2, sClientSteamID, sizeof(sClientSteamID));

	char sClientFlagString[64];
	GetClientFlagString(client, sClientFlagString, sizeof(sClientFlagString));

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(sClientSteamID);
	pack.WriteString(sClientFlagString);

	SQLSelect_Tag(INVALID_HANDLE, pack);

	return Plugin_Stop;
}

stock Action SQLSelect_Tag(Handle timer, any data)
{
	if (g_hDatabase == null)
		return Plugin_Stop;

	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char sClientSteamID[32];

	pack.ReadCell();
	pack.ReadString(sClientSteamID, sizeof(sClientSteamID));

	char sQuery[256];

	Format(sQuery, sizeof(sQuery), "SELECT `steamid`, `enable`, `tag`, `tag_color`, `name_color`, `chat_color` FROM `ccc_tag` WHERE `steamid` = '%s';", sClientSteamID);
	SQL_TQuery(g_hDatabase, OnSQLSelect_Tag, sQuery, data, DBPrio_High);
	return Plugin_Stop;
}

stock Action SQLInsert_Replace(Handle timer, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char sQuery[256];
	char sTrigger[MAX_CHAT_TRIGGER_LENGTH];
	char sValue[MAX_CHAT_LENGTH];

	pack.ReadCell();
	pack.ReadString(sTrigger, sizeof(sTrigger));
	pack.ReadString(sValue, sizeof(sValue));

	Format(sQuery, sizeof(sQuery), "INSERT INTO `ccc_replace` (`trigger`, `value`) VALUES ('%s', '%s');", sTrigger, sValue);
	SQL_TQuery(g_hDatabase, OnSQLInsert_Replace, sQuery, data);
	return Plugin_Stop;
}

stock Action SQLDelete_Replace(Handle timer, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char sQuery[256];
	char sTrigger[MAX_CHAT_TRIGGER_LENGTH];

	pack.ReadCell();
	pack.ReadString(sTrigger, sizeof(sTrigger));

	Format(sQuery, sizeof(sQuery), "DELETE FROM `ccc_replace` WHERE `trigger` = '%s';", sTrigger);
	SQL_TQuery(g_hDatabase, OnSQLDelete_Replace, sQuery, data);
	return Plugin_Stop;
}

stock Action SQLInsert_TagClient(Handle timer, any client)
{
	char sClientSteamID[32];
	char sClientName[32];

	GetClientAuthId(client, AuthId_Steam2, sClientSteamID, sizeof(sClientSteamID));
	GetClientName(client, sClientName, sizeof(sClientName));

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(sClientSteamID);
	pack.WriteCell(g_iClientEnable[client]);
	pack.WriteString(sClientName);
	pack.WriteString("");
	pack.WriteString(g_sClientTag[client]);
	pack.WriteString(g_sClientTagColor[client]);
	pack.WriteString(g_sClientNameColor[client]);
	pack.WriteString(g_sClientChatColor[client]);

	SQLInsert_Tag(INVALID_HANDLE, pack);

	return Plugin_Stop;
}

stock Action SQLInsert_Tag(Handle timer, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char sSteamID[64];
	char sName[32];
	char sFlag[32];
	char sTag[32];
	char sTagColor[32];
	char sNameColor[32];
	char sChatColor[32];

	pack.ReadCell();
	pack.ReadString(sSteamID, sizeof(sSteamID));
	int iEnable = pack.ReadCell();
	pack.ReadString(sName, sizeof(sName));
	pack.ReadString(sFlag, sizeof(sFlag));
	pack.ReadString(sTag, sizeof(sTag));
	pack.ReadString(sTagColor, sizeof(sTagColor));
	pack.ReadString(sNameColor, sizeof(sNameColor));
	pack.ReadString(sChatColor, sizeof(sChatColor));

	char sQuery[256];

	Format(
		sQuery,
		sizeof(sQuery),
		"INSERT INTO `ccc_tag` (`steamid`, `name`, `enable`, `flag`, `tag`, `tag_color`, `name_color`, `chat_color`) VALUES ('%s', '%s', '%d', '%s', '%s', '%s', '%s', '%s');",
		sSteamID,
		sName,
		iEnable,
		sFlag,
		sTag,
		sTagColor,
		sNameColor,
		sChatColor
	);
	SQL_TQuery(g_hDatabase, OnSQLInsert_Tag, sQuery, data);
	return Plugin_Stop;
}

stock Action SQLUpdate_TagClient(Handle timer, any client)
{
	char sClientSteamID[32];
	char sClientName[32];

	GetClientAuthId(client, AuthId_Steam2, sClientSteamID, sizeof(sClientSteamID));
	GetClientName(client, sClientName, sizeof(sClientName));

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(sClientSteamID);
	pack.WriteCell(g_iClientEnable[client]);
	pack.WriteString(sClientName);
	pack.WriteString("");
	pack.WriteString(g_sClientTag[client]);
	pack.WriteString(g_sClientTagColor[client]);
	pack.WriteString(g_sClientNameColor[client]);
	pack.WriteString(g_sClientChatColor[client]);

	SQLUpdate_Tag(INVALID_HANDLE, pack);

	return Plugin_Stop;
}

stock Action SQLUpdate_Tag(Handle timer, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char sSteamID[64];
	char sName[32];
	char sFlag[32];
	char sTag[32];
	char sTagColor[32];
	char sNameColor[32];
	char sChatColor[32];

	pack.ReadCell();
	pack.ReadString(sSteamID, sizeof(sSteamID));
	int iEnable = pack.ReadCell();
	pack.ReadString(sName, sizeof(sName));
	pack.ReadString(sFlag, sizeof(sFlag));
	pack.ReadString(sTag, sizeof(sTag));
	pack.ReadString(sTagColor, sizeof(sTagColor));
	pack.ReadString(sNameColor, sizeof(sNameColor));
	pack.ReadString(sChatColor, sizeof(sChatColor));

	char sQuery[256];

	Format(
		sQuery,
		sizeof(sQuery),
		"UPDATE `ccc_tag` SET `name` = '%d', `enable` = '%d', `flag` = '%s', `tag` = '%s', `tag_color` = '%s', `name_color` = '%s', `chat_color` = '%s' WHERE `steamid` = '%s';",
		sName,
		iEnable,
		sFlag,
		sTag,
		sTagColor,
		sNameColor,
		sChatColor,
		sSteamID
	);
	SQL_TQuery(g_hDatabase, OnSQLUpdate_Tag, sQuery, data);
	return Plugin_Stop;
}

stock Action SQLDelete_Tag(Handle timer, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char sSteamID[64];

	pack.ReadCell();
	pack.ReadString(sSteamID, sizeof(sSteamID));

	char sQuery[256];

	Format(sQuery, sizeof(sQuery), "DELETE FROM `ccc_tag` WHERE `steamid` = '%s';", sSteamID);
	SQL_TQuery(g_hDatabase, OnSQLDelete_Tag, sQuery, data);

	return Plugin_Stop;
}

stock void OnSqlSetNames(Handle hParent, Handle hChild, const char[] err, any data)
{
	if (hChild == null)
	{
		LogError("Database error while setting names as utf8, retrying in 10 seconds. (%s)", err);
		CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLSetNames);

		return;
	}
	SQLSelect_Replace(INVALID_HANDLE);
}

public void OnSQLDelete_Tag(Handle hParent, Handle hChild, const char[] err, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();

	if (hChild == null)
	{
		if (g_bSQLDeleteTagRetry[client] + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLDeleteTagRetry[client]++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLDelete_Tag, data);
			return;
		}
	}

	g_bSQLDeleteTagRetry[client] = 0;

	delete pack;
}

stock Action SQLInsert_Ban(Handle timer, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();
	int target = pack.ReadCell();

	char sTime[128];
	pack.ReadString(sTime, sizeof(sTime));

	int time = StringToInt(sTime);
	time = GetTime() + (time * 60);

	if (StringToInt(sTime) == 0)
	{
		time = 0;
	}

	char sQuery[256];
	char sClientName[32];
	char sTargetName[32];
	char sClientSteamID[32];
	char sTargetSteamID[32];

	GetClientName(client, sClientName, sizeof(sClientName));
	GetClientName(target, sTargetName, sizeof(sTargetName));
	GetClientAuthId(client, AuthId_Steam2, sClientSteamID, sizeof(sClientSteamID));
	GetClientAuthId(target, AuthId_Steam2, sTargetSteamID, sizeof(sTargetSteamID));

	Format(sQuery, sizeof(sQuery), "INSERT INTO `ccc_ban` (`steamid`, `name`, `issuer_steamid`, `issuer_name`, `length`) VALUES ('%s', '%s', '%s', '%s', '%d');", sTargetSteamID, sTargetName, sClientSteamID, sClientName, time);
	SQL_TQuery(g_hDatabase, OnSQLInsert_Ban, sQuery, data);

	return Plugin_Stop;
}

stock Action SQLDelete_Ban(Handle timer, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	// client
	pack.ReadCell();
	// target
	int target = pack.ReadCell();

	char sQuery[256];
	char sTargetSteamID[32];

	GetClientAuthId(target, AuthId_Steam2, sTargetSteamID, sizeof(sTargetSteamID));
	Format(sQuery, sizeof(sQuery), "DELETE FROM `ccc_ban` WHERE `steamid` = '%s';", sTargetSteamID);
	SQL_TQuery(g_hDatabase, OnSQLDelete_Ban, sQuery, data);

	return Plugin_Stop;
}

public void OnSQLTableCreated_Tag(Handle hParent, Handle hChild, const char[] err, any data)
{
	if (hChild == null)
	{
		LogError("Database error while creating/checking for \"ccc_tag\" table, retrying in 10 seconds. (%s)", DATABASE_NAME, err);
		CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLTableCreation_Tag);

		return;
	}
}

public void OnSQLTableCreated_Ban(Handle hParent, Handle hChild, const char[] err, any data)
{
	if (hChild == null)
	{
		LogError("Database error while creating/checking for \"ccc_ban\" table, retrying in 10 seconds. (%s)", DATABASE_NAME, err);
		CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLTableCreation_Ban);

		return;
	}
}

public void OnSQLTableCreated_Replace(Handle hParent, Handle hChild, const char[] err, any data)
{
	if (hChild == null)
	{
		LogError("Database error while creating/checking for \"ccc_replace\" table, retrying in 10 seconds. (%s)", DATABASE_NAME, err);
		CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLTableCreation_Replace);

		return;
	}
}

public void OnSQLSelect_Replace(Handle hParent, Handle hChild, const char[] err, any client)
{
	if (hChild == null)
	{
		LogError("An error occurred while querying the database for the replace list, retrying in %d seconds. (%s)", GetConVarFloat(g_cvar_SQLRetryTime), err);

		if (g_bSQLSelectReplaceRetry + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLSelectReplaceRetry++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLSelect_Replace, client);
			return;
		}
	}
	else
	{
		while (SQL_FetchRow(hChild))
		{
			SQL_FetchString(hChild, 0, g_sReplaceList[g_iReplaceListSize][0], sizeof(g_sReplaceList[][]));
			SQL_FetchString(hChild, 1, g_sReplaceList[g_iReplaceListSize][1], sizeof(g_sReplaceList[][]));
			ReplaceString(g_sReplaceList[g_iReplaceListSize][1], sizeof(g_sReplaceList[][]), "\r\n", "\n");
			g_iReplaceListSize++;
		}
	}

	g_bSQLSelectReplaceRetry = 0;
}

public void OnSQLSelect_Ban(Handle hParent, Handle hChild, const char[] err, any client)
{
	if (hChild == null)
	{
		LogError("An error occurred while querying the database for the user tag, retrying in %d seconds. (%s)", GetConVarFloat(g_cvar_SQLRetryTime), err);

		if (g_bSQLSelectBanRetry[client] + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLSelectBanRetry[client]++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLSelect_Ban, client);
			return;
		}
	}
	else if (SQL_FetchRow(hChild))
	{
		g_iClientBanned[client] = SQL_FetchInt(hChild, 0);
	}

	g_bSQLSelectBanRetry[client] = 0;
}

stock void OnSQLSelect_TagGroup(Handle hParent, Handle hChild, const char[] err, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();

	g_sClientSID[client] = "";

	if (hChild == null)
	{
		LogError("An error occurred while querying the database for the user group tag, retrying in %d seconds. (%s)", GetConVarFloat(g_cvar_SQLRetryTime), err);

		if (g_bSQLSelectTagGroupRetry[client] + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLSelectTagGroupRetry[client]++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLSelect_TagGroup, data);
			return;
		}
	}
	else if (SQL_FetchRow(hChild))
	{
		// pack.ReadString(g_sClientSID[client], sizeof(g_sClientSID[]));

		g_iClientEnable[client] = SQL_FetchInt(hChild, 1);
		SQL_FetchString(hChild, 2, g_sClientTag[client], sizeof(g_sClientTag[]));
		SQL_FetchString(hChild, 3, g_sClientTagColor[client], sizeof(g_sClientTagColor[]));
		SQL_FetchString(hChild, 4, g_sClientNameColor[client], sizeof(g_sClientNameColor[]));
		SQL_FetchString(hChild, 5, g_sClientChatColor[client], sizeof(g_sClientChatColor[]));

		g_iDefaultClientEnable[client] = g_iClientEnable[client];
		strcopy(g_sDefaultClientTag[client], sizeof(g_sDefaultClientTag[]), g_sClientTag[client]);
		strcopy(g_sDefaultClientTagColor[client], sizeof(g_sDefaultClientTagColor[]), g_sClientTagColor[client]);
		strcopy(g_sDefaultClientNameColor[client], sizeof(g_sDefaultClientNameColor[]), g_sClientNameColor[client]);
		strcopy(g_sDefaultClientChatColor[client], sizeof(g_sDefaultClientChatColor[]), g_sClientChatColor[client]);
	}

	g_bSQLSelectTagGroupRetry[client] = 0;

	delete pack;
}

public void OnSQLSelect_Tag(Handle hParent, Handle hChild, const char[] err, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();

	g_sClientSID[client] = "";

	if (hChild == null)
	{
		LogError("An error occurred while querying the database for the user tag, retrying in %d seconds. (%s)", GetConVarFloat(g_cvar_SQLRetryTime), err);

		if (g_bSQLSelectTagRetry[client] + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLSelectTagRetry[client]++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLSelect_Tag, data);
			return;
		}
	}
	else if (SQL_FetchRow(hChild))
	{
		SQL_FetchString(hChild, 0, g_sClientSID[client], sizeof(g_sClientSID[]));
		g_iClientEnable[client] = SQL_FetchInt(hChild, 1);
		SQL_FetchString(hChild, 2, g_sClientTag[client], sizeof(g_sClientTag[]));
		SQL_FetchString(hChild, 3, g_sClientTagColor[client], sizeof(g_sClientTagColor[]));
		SQL_FetchString(hChild, 4, g_sClientNameColor[client], sizeof(g_sClientNameColor[]));
		SQL_FetchString(hChild, 5, g_sClientChatColor[client], sizeof(g_sClientChatColor[]));

		g_iDefaultClientEnable[client] = g_iClientEnable[client];
		strcopy(g_sDefaultClientTag[client], sizeof(g_sDefaultClientTag[]), g_sClientTag[client]);
		strcopy(g_sDefaultClientTagColor[client], sizeof(g_sDefaultClientTagColor[]), g_sClientTagColor[client]);
		strcopy(g_sDefaultClientNameColor[client], sizeof(g_sDefaultClientNameColor[]), g_sClientNameColor[client]);
		strcopy(g_sDefaultClientChatColor[client], sizeof(g_sDefaultClientChatColor[]), g_sClientChatColor[client]);

		Call_StartForward(loadedForward);
		Call_PushCell(client);
		Call_Finish();
	}
	else
	{
		g_bSQLSelectTagRetry[client] = 0;
		SQLSelect_TagGroup(INVALID_HANDLE, data);
		return;
	}

	g_bSQLSelectTagRetry[client] = 0;

	delete pack;
}

public void OnSQLUpdate_Tag(Handle hParent, Handle hChild, const char[] err, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();

	if (hChild == null)
	{
		LogError("An error occurred while updating an user tag, retrying in %d seconds. (%s)", GetConVarFloat(g_cvar_SQLRetryTime), err);

		if (g_bSQLUpdateTagRetry[client] + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLUpdateTagRetry[client]++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLUpdate_Tag, data);
			return;
		}
	}

	ResetClient(client);
	g_bSQLUpdateTagRetry[client] = 0;

	delete pack;
}

public void OnSQLInsert_Replace(Handle hParent, Handle hChild, const char[] err, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();

	if (hChild == null)
	{
		LogError("An error occurred while inserting a chat trigger, retrying in %d seconds. (%s)", GetConVarFloat(g_cvar_SQLRetryTime), err);
		if (g_bSQLInsertReplaceRetry[client] + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLInsertReplaceRetry[client]++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLInsert_Replace, data);
			return;
		}
	}
	else
	{
		char sTrigger[MAX_CHAT_TRIGGER_LENGTH];
		char sValue[MAX_CHAT_LENGTH];

		pack.ReadString(sTrigger, sizeof(sTrigger));
		pack.ReadString(sValue, sizeof(sValue));

		g_sReplaceList[g_iReplaceListSize][0] = sTrigger;
		g_sReplaceList[g_iReplaceListSize][1] = sValue;
		g_iReplaceListSize++;
	}

	g_bSQLInsertReplaceRetry[client] = 0;

	delete pack;
}

public void OnSQLDelete_Replace(Handle hParent, Handle hChild, const char[] err, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();

	if (hChild == null)
	{
		if (g_bSQLDeleteReplaceRetry[client] + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLDeleteReplaceRetry[client]++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLDelete_Replace, data);
			return;
		}
	}
	else
	{
		char sTrigger[MAX_CHAT_TRIGGER_LENGTH];
		pack.ReadString(sTrigger, sizeof(sTrigger));

		for (int i = 0; i < g_iReplaceListSize; i++)
		{
			if (StrEqual(sTrigger, g_sReplaceList[i][0]))
			{
				for (int y = i; y < g_iReplaceListSize; y++)
				{
					if (y + 1 < g_iReplaceListSize)
					{
						g_sReplaceList[y][0] = g_sReplaceList[y + 1][0];
						g_sReplaceList[y][1] = g_sReplaceList[y + 1][1];
					}
					else
					{
						g_sReplaceList[y][0] = "";
						g_sReplaceList[y][1] = "";
					}
				}
				g_iReplaceListSize--;

				break;
			}
		}
	}

	g_bSQLDeleteReplaceRetry[client] = 0;

	delete pack;
}

public void OnSQLInsert_Tag(Handle hParent, Handle hChild, const char[] err, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();

	if (hChild == null)
	{
		LogError("An error occurred while inserting an user tag, retrying in %d seconds. (%s)", GetConVarFloat(g_cvar_SQLRetryTime), err);
		if (g_bSQLInsertTagRetry[client] + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLInsertTagRetry[client]++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLInsert_Tag, data);
			return;
		}
	}

	g_bSQLInsertTagRetry[client] = 0;

	delete pack;
}

public void OnSQLInsert_Ban(Handle hParent, Handle hChild, const char[] err, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	pack.ReadCell();
	int target = pack.ReadCell();

	if (hChild == null)
	{
		if (g_bSQLInsertBanRetry[target] + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLInsertBanRetry[target]++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLInsert_Ban, data);
			return;
		}
	}
	else
	{
		char sTime[128];
		pack.ReadString(sTime, sizeof(sTime));

		int time = StringToInt(sTime);
		time = GetTime() + (time * 60);

		if (StringToInt(sTime) == 0)
		{
			time = 0;
		}

		g_iClientBanned[target] = time;
	}

	g_bSQLInsertBanRetry[target] = 0;

	delete pack;
}

public void OnSQLDelete_Ban(Handle hParent, Handle hChild, const char[] err, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	pack.ReadCell();
	int target = pack.ReadCell();

	if (hChild == null)
	{
		if (g_bSQLDeleteBanRetry[target] + 1 < GetConVarInt(g_cvar_SQLMaxRetries))
		{
			g_bSQLDeleteBanRetry[target]++;
			CreateTimer(GetConVarFloat(g_cvar_SQLRetryTime), SQLDelete_Ban, data);
			return;
		}
	}
	else
	{
		g_iClientBanned[target] = -1;
	}

	g_bSQLDeleteBanRetry[target] = 0;

	delete pack;
}

/* public OnLibraryRemoved(const char name[])
{
	if (StrEqual(name, "adminmenu"))
	{
		g_hAdminMenu = null;
	}
}

public OnAdminMenuReady(Handle CCCAMenu)
{
	if (CCCAMenu == g_hAdminMenu)
	{
		return;
	}

	g_hAdminMenu = CCCAMenu;
	new TopMenuObject:MenuObject = AddToTopMenu(g_hAdminMenu, "CCCCmds", TopMenuObject_Category, Handle_Commands, INVALID_TOPMENUOBJECT);

	if (MenuObject == INVALID_TOPMENUOBJECT)
	{
		return;
	}

	AddToTopMenu(g_hAdminMenu, "CCCReset", TopMenuObject_Item, Handle_AMenuReset, MenuObject, "sm_cccreset", ADMFLAG_SLAY);
	AddToTopMenu(g_hAdminMenu, "CCCBan", TopMenuObject_Item, Handle_AMenuBan, MenuObject, "sm_cccban", ADMFLAG_SLAY);
	AddToTopMenu(g_hAdminMenu, "CCCUnBan", TopMenuObject_Item, Handle_AMenuUnBan, MenuObject, "sm_cccunban", ADMFLAG_SLAY);
} */

bool MakeStringPrintable(char[] str, int str_len_max, const char[] empty) //function taken from Forlix FloodCheck (http://forlix.org/gameaddons/floodcheck.shtml)
{
	int r = 0;
	int w = 0;
	bool modified = false;
	bool nonspace = false;
	bool addspace = false;

	if (str[0])
	{
		do
		{
			if (str[r] < '\x20')
			{
			  modified = true;

			  if((str[r] == '\n' || str[r] == '\t') && w > 0 && str[w-1] != '\x20')
				addspace = true;
			}
			else
			{
			  if (str[r] != '\x20')
			  {
				nonspace = true;

				if (addspace)
				  str[w++] = '\x20';
			  }

			  addspace = false;
			  str[w++] = str[r];
			}
		}
		while(str[++r]);
	}

	str[w] = '\0';

	if (!nonspace)
	{
		modified = true;
		strcopy(str, str_len_max, empty);
	}

	return (modified);
}

bool SingularOrMultiple(int num)
{
	if (num > 1 || num == 0)
	{
		return true;
	}

	return false;
}

bool HasFlag(int client, AdminFlag ADMFLAG)
{
	AdminId Admin = GetUserAdmin(client);

	if (Admin != INVALID_ADMIN_ID && GetAdminFlag(Admin, ADMFLAG, Access_Effective))
		return true;

	return false;
}

bool ForceColor(int client, char Key[64])
{
	int iTarget;
	char sTarget[64];
	char sCol[64];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	GetCmdArg(2, sCol, sizeof(sCol));

	if (IsValidRGBNum(sCol))
	{
		char g[8];
		char b[8];
		GetCmdArg(3, g, sizeof(g));
		GetCmdArg(4, b, sizeof(b));
		int hex;

		hex |= ((StringToInt(sCol) & 0xFF) << 16);
		hex |= ((StringToInt(g) & 0xFF) << 8);
		hex |= ((StringToInt(b) & 0xFF) << 0);

		Format(sCol, 64, "#%06X", hex);
	}

	if ((iTarget = FindTarget(client, sTarget, true)) == -1)
	{
		return false;
	}

	char SID[64];
	GetClientAuthId(iTarget, AuthId_Steam2, SID, sizeof(SID));

	if (IsSource2009() && IsValidHex(sCol))
	{
		if (sCol[0] != '#')
			Format(sCol, sizeof(sCol), "#%s", sCol);

		SetColor(SID, Key, sCol, -1, true);

		if (sCol[0] == '#' && IsSource2009())
		{
			if (!strcmp(Key, "namecolor"))
				CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} name color to: \x07%s%s{default}!", iTarget, sCol[0], sCol[0]);
			else if (!strcmp(Key, "tagcolor"))
				CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} tag color to: \x07%s%s{default}!", iTarget, sCol[0], sCol[0]);
			else
				CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} text color to: \x07%s%s{default}!", iTarget, sCol[0], sCol[0]);
		}
	}
	else if (!IsSource2009())
	{
		StringMap smTrie = MC_GetTrie();
		char value[32];
		if (!smTrie.GetString(sCol, value, sizeof(value)))
		{
			CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid color name given.");
			return false;
		}

		SetColor(SID, Key, sCol, -1, true);

		if (!strcmp(Key, "namecolor"))
			CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} name color to: {%s}%s{default}!", iTarget, sCol[0], sCol[0]);
		else if (!strcmp(Key, "tagcolor"))
			CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} tag color to: {%s}%s{default}!", iTarget, sCol[0], sCol[0]);
		else
			CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} text color to: {%s}%s{default}!", iTarget, sCol[0], sCol[0]);
	}
	else
	{
		CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid HEX|RGB color code given.");
	}

	return true;
}

bool IsValidRGBNum(char[] arg)
{
	if (SimpleRegexMatch(arg, "^([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])$") == 2)
	{
		return true;
	}

	return false;
}

bool IsValidHex(char[] arg)
{
	if (SimpleRegexMatch(arg, "^(#?)([A-Fa-f0-9]{6})$") == 0)
	{
		return false;
	}

	return true;
}

stock bool IsClientBanned(int client, bool bNotify = false, const char Key[64] = "")
{
	if (g_iClientBanned[client] == 0)
	{
		CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} You are currently {red}permanently banned{default} from changing your {green}%s{default}.", Key);
		return true;
	}
	else if (g_iClientBanned[client] >= GetTime())
	{
		char TimeBuffer[64];
		int tstamp = g_iClientBanned[client];
		tstamp = (tstamp - GetTime());

		int days = (tstamp / 86400);
		int hrs = ((tstamp / 3600) % 24);
		int mins = ((tstamp / 60) % 60);
		int sec = (tstamp % 60);

		if (tstamp > 86400)
		{
			Format(TimeBuffer, sizeof(TimeBuffer), "%d %s, %d %s, %d %s, %d %s", days, SingularOrMultiple(days) ? "Days" : "Day", hrs, SingularOrMultiple(hrs) ? "Hours" : "Hour", mins, SingularOrMultiple(mins) ? "Minutes" : "Minute", sec, SingularOrMultiple(sec) ? "Seconds" : "Second");
		}
		else if (tstamp > 3600)
		{
			Format(TimeBuffer, sizeof(TimeBuffer), "%d %s, %d %s, %d %s", hrs, SingularOrMultiple(hrs) ? "Hours" : "Hour", mins, SingularOrMultiple(mins) ? "Minutes" : "Minute", sec, SingularOrMultiple(sec) ? "Seconds" : "Second");
		}
		else if (tstamp > 60)
		{
			Format(TimeBuffer, sizeof(TimeBuffer), "%d %s, %d %s", mins, SingularOrMultiple(mins) ? "Minutes" : "Minute", sec, SingularOrMultiple(sec) ? "Seconds" : "Second");
		}
		else
		{
			Format(TimeBuffer, sizeof(TimeBuffer), "%d %s", sec, SingularOrMultiple(sec) ? "Seconds" : "Second");
		}

		CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} You are currently {red}banned{default} from changing your {green}%s{default}. (Time remaining: {green}%s{default})", Key, TimeBuffer);
		return true;
	}
	return false;
}

stock bool SetColor(char SID[64], char Key[64], char HEX[64], int client, bool IgnoreBan=false)
{
	if (!IgnoreBan)
	{
		if (IsClientBanned(client, true, Key))
			return false;
	}

	if (StrEqual(Key, "tagcolor"))
	{
		if (HEX[0] == '#')
			ReplaceString(HEX, sizeof(HEX), "#", "");
		strcopy(g_sClientTagColor[client], sizeof(g_sClientTagColor[]), HEX);
	}
	else if (StrEqual(Key, "namecolor"))
	{
		if (HEX[0] == '#')
			ReplaceString(HEX, sizeof(HEX), "#", "");
		strcopy(g_sClientNameColor[client], sizeof(g_sClientNameColor[]), HEX);
	}
	else if (StrEqual(Key, "textcolor"))
	{
		if (HEX[0] == '#')
			ReplaceString(HEX, sizeof(HEX), "#", "");
		strcopy(g_sClientChatColor[client], sizeof(g_sClientChatColor[]), HEX);
	}

	return true;
}

stock bool SetTag(char SID[64], char text[64], int client, bool IgnoreBan=false)
{
	if (!IgnoreBan)
	{
		if (IsClientBanned(client, true, "Tag"))
			return false;
	}

	Format(g_sClientTag[client], sizeof(g_sClientTag[]), "%s ", text);

	return true;
}

stock bool RemoveCCC(char SID[64], int client)
{
	ResetClient(client);

	return true;
}

stock void BanCCC(char SID[64], int client, int target, char Time[128])
{
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(target);
	pack.WriteString(Time);

	SQLInsert_Ban(INVALID_HANDLE, pack);
}

stock void UnBanCCC(char SID[64], int client, int target)
{
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(target);

	SQLDelete_Ban(INVALID_HANDLE, pack);
}

stock void ToggleCCC(char SID[64], int client)
{
	g_iClientEnable[client] = g_iClientEnable[client] ? 0 : 1;
}

void SendChatToAdmins(int from, const char[] message)
{
	int fromAdmin = CheckCommandAccess(from, "sm_chat", ADMFLAG_CHAT);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && (from == i || CheckCommandAccess(i, "sm_chat", ADMFLAG_CHAT)))
		{
			CPrintToChat(i, "%s(%sADMINS) %s%N{default} : %s%s", g_sSmCategoryColor, fromAdmin ? "" : "TO ", 
				g_sSmNameColor, from, g_sSmChatColor, message);
		}
	}
}

void SendPrivateChat(int client, int target, const char[] message)
{
	if (!client)
	{
		PrintToServer("(Private to %N) %N: %s", target, client, message);
	}
	else if (target != client)
	{
		CPrintToChat(client, "%s(Private to %s%N%s) %s%N {default}: %s%s", g_sSmCategoryColor, g_sSmNameColor, target,
			g_sSmCategoryColor, g_sSmNameColor, client, g_sSmChatColor, message);
	}

	CPrintToChat(target, "%s(Private to %s%N%s) %s%N {default}: %s%s", g_sSmCategoryColor, g_sSmNameColor, target,
		g_sSmCategoryColor, g_sSmNameColor, client, g_sSmChatColor, message);
	LogAction(client, target, "\"%L\" triggered sm_psay to \"%L\" (text %s)", client, target, message);
}

void SendChatToAll(int client, const char[] message)
{
	if (!CheckCommandAccess(client, "sm_say", ADMFLAG_CHAT))
		return;

	char nameBuf[MAX_NAME_LENGTH];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}
		FormatActivitySource(client, i, nameBuf, sizeof(nameBuf));
		
		CPrintToChat(i, "%s(ALL) %s%s {default}: %s%s", g_sSmCategoryColor, g_sSmNameColor, nameBuf, g_sSmChatColor, message);
	}
}

//   .d8888b.   .d88888b.  888b     d888 888b     d888        d8888 888b    888 8888888b.   .d8888b.
//  d88P  Y88b d88P" "Y88b 8888b   d8888 8888b   d8888       d88888 8888b   888 888  "Y88b d88P  Y88b
//  888    888 888     888 88888b.d88888 88888b.d88888      d88P888 88888b  888 888    888 Y88b.
//  888        888     888 888Y88888P888 888Y88888P888     d88P 888 888Y88b 888 888    888  "Y888b.
//  888        888     888 888 Y888P 888 888 Y888P 888    d88P  888 888 Y88b888 888    888     "Y88b.
//  888    888 888     888 888  Y8P  888 888  Y8P  888   d88P   888 888  Y88888 888    888       "888
//  Y88b  d88P Y88b. .d88P 888   "   888 888   "   888  d8888888888 888   Y8888 888  .d88P Y88b  d88P
//   "Y8888P"   "Y88888P"  888       888 888       888 d88P     888 888    Y888 8888888P"   "Y8888P"
//

public Action Command_CCCImportReplaceFile(int client, int argc)
{
	if (argc != 1)
	{
		CReplyToCommand(client, "{green}[CCC]{white} Usage: sm_cccimportreplacefile filename");
		return Plugin_Handled;
	}

	char sFilename[128];
	GetCmdArg(1, sFilename, sizeof(sFilename));

	char sFilepath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilepath, sizeof(sFilepath), "configs/%s", sFilename);

	KeyValues kv = new KeyValues("AutoReplace");

	if (!kv.ImportFromFile(sFilepath))
	{
		CReplyToCommand(client, "{green}[CCC]{white} File missing, please make sure \"%s\" is in the \"sourcemod/configs\" folder.", sFilepath);
		return Plugin_Handled;
	}

	if (!kv.GotoFirstSubKey(false))
	{
		delete kv;
		return Plugin_Handled;
	}

	char sTrigger[MAX_CHAT_TRIGGER_LENGTH];
	char sValue[MAX_CHAT_LENGTH];
	do
	{
		kv.GetSectionName(sTrigger, sizeof(sTrigger));
		kv.GetString(NULL_STRING, sValue, sizeof(sValue));

		DataPack pack = new DataPack();
		pack.WriteCell(client);
		pack.WriteString(sTrigger);
		pack.WriteString(sValue);

		SQLInsert_Replace(INVALID_HANDLE, pack);

	} while (kv.GotoNextKey(false));

	delete kv;
	return Plugin_Handled;
}

public Action Command_CCCAddTag(int client, int argc)
{
	if (argc != 8)
	{
		CReplyToCommand(client, "{green}[CCC]{white} Usage: sm_cccaddtag steamid enable name flag tag tag_color name_color chat_color");
		return Plugin_Handled;
	}

	char sSteamID[64];
	char sEnable[2];
	char sName[32];
	char sFlag[32];
	char sTag[32];
	char sTagColor[32];
	char sNameColor[32];
	char sChatColor[32];

	GetCmdArg(1, sSteamID, sizeof(sSteamID));
	GetCmdArg(2, sEnable, sizeof(sEnable));
	GetCmdArg(3, sName, sizeof(sName));
	GetCmdArg(4, sFlag, sizeof(sFlag));
	GetCmdArg(5, sTag, sizeof(sTag));
	GetCmdArg(6, sTagColor, sizeof(sTagColor));
	GetCmdArg(7, sNameColor, sizeof(sNameColor));
	GetCmdArg(8, sChatColor, sizeof(sChatColor));

	if (strlen(sEnable) == 1 && strlen(sName) > 0 &&
		strlen(sTagColor) <= 6 && strlen(sNameColor) <= 6 && strlen(sChatColor) <= 6)
	{
		DataPack pack = new DataPack();
		pack.WriteCell(client);
		pack.WriteString(sSteamID);
		pack.WriteCell(StringToInt(sEnable));
		pack.WriteString(sName);
		pack.WriteString(sFlag);
		pack.WriteString(sTag);
		pack.WriteString(sTagColor);
		pack.WriteString(sNameColor);
		pack.WriteString(sChatColor);

		SQLInsert_Tag(INVALID_HANDLE, pack);
	}
	else
	{
		CReplyToCommand(client, "{green}[CCC]{white} Wrong parameters.");
	}

	return Plugin_Handled;
}

public Action Command_CCCDeleteTag(int client, int argc)
{
	if (argc != 8)
	{
		CReplyToCommand(client, "{green}[CCC]{white} Usage: sm_cccdeletetag steamid");
		return Plugin_Handled;
	}

	char sSteamID[64];

	GetCmdArg(1, sSteamID, sizeof(sSteamID));

	if (strlen(sSteamID) > 0)
	{
		DataPack pack = new DataPack();
		pack.WriteCell(client);
		pack.WriteString(sSteamID);

		SQLDelete_Tag(INVALID_HANDLE, pack);
	}
	else
	{
		CReplyToCommand(client, "{green}[CCC]{white} Wrong parameter.");
	}

	return Plugin_Handled;
}

public Action Command_CCCAddTrigger(int client, int argc)
{
	if (argc != 2)
	{
		CReplyToCommand(client, "{green}[CCC]{white} Usage: sm_cccaddtrigger trigger value");
		return Plugin_Handled;
	}

	char sTrigger[MAX_CHAT_TRIGGER_LENGTH];
	char sValue[MAX_CHAT_LENGTH];

	GetCmdArg(1, sTrigger, sizeof(sTrigger));
	GetCmdArg(2, sValue, sizeof(sValue));
	
	if (sTrigger[0] == '\0')
	{
		CReplyToCommand(client, "{green}[CCC]{white} Trigger must be non empty");
		return Plugin_Handled;
	}

	if (sValue[0] == '\0')
	{
		CReplyToCommand(client, "{green}[CCC]{white} Value must be non empty");
		return Plugin_Handled;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(sTrigger);
	pack.WriteString(sValue);

	SQLInsert_Replace(INVALID_HANDLE, pack);

	return Plugin_Handled;
}

public Action Command_CCCDeleteTrigger(int client, int argc)
{
	if (argc != 1)
	{
		CReplyToCommand(client, "{green}[CCC]{white} Usage: sm_cccdeletetrigger trigger");
		return Plugin_Handled;
	}

	char sTrigger[MAX_CHAT_TRIGGER_LENGTH];

	GetCmdArg(1, sTrigger, sizeof(sTrigger));
	
	if (sTrigger[0] == '\0')
	{
		CReplyToCommand(client, "{green}[CCC]{white} Trigger must be non empty");
		return Plugin_Handled;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(sTrigger);

	SQLDelete_Replace(INVALID_HANDLE, pack);

	return Plugin_Handled;
}

public Action Command_ReloadConfig(int client, int args)
{
	LateLoad();

	LogAction(client, -1, "Reloaded Custom Chat Colors");
	ReplyToCommand(client, "[CCC] Reloaded ccc.");
	Call_StartForward(configReloadedForward);
	Call_Finish();
	return Plugin_Handled;
}

public Action Command_TagMenu(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[CCC] Cannot use command from server console");
		return Plugin_Handled;
	}

	Menu_Main(client);
	return Plugin_Stop;
}

public Action Command_SmSay(int client, const char[] command, int argc)
{
	if (argc < 1)
		return Plugin_Continue;
	
	char text[192];
	GetCmdArgString(text, sizeof(text));

	SendChatToAll(client, text);
	LogAction(client, -1, "\"%L\" triggered sm_say (text %s)", client, text);
	
	return Plugin_Stop;		
}

public Action Command_SmChat(int client, const char[] command, int argc)
{
	if (argc < 1)
		return Plugin_Continue;
	
	char text[192];
	GetCmdArgString(text, sizeof(text));

	SendChatToAdmins(client, text);
	LogAction(client, -1, "\"%L\" triggered sm_chat (text %s)", client, text);
	
	return Plugin_Stop;
}

public Action Command_SmPSay(int client, const char[] command, int argc)
{
	if (argc < 2)
		return Plugin_Continue;	

	char text[192], arg[64], message[192];
	GetCmdArgString(text, sizeof(text));

	int len = BreakString(text, arg, sizeof(arg));
	BreakString(text[len], message, sizeof(message));

	int target = FindTarget(client, arg, true, false);

	if (target == -1)
		return Plugin_Handled;

	SendPrivateChat(client, target, message);

	return Plugin_Stop;
}

public Action Command_Say(int client, const char[] command, int argc)
{
	if (client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		char text[MAX_CHAT_LENGTH];
		GetCmdArgString(text, sizeof(text));

		if (!HasFlag(client, Admin_Generic) || !HasFlag(client, Admin_Custom1))
		{
			if (MakeStringPrintable(text, sizeof(text), ""))
			{
				return Plugin_Handled;
			}
		}

		if (g_bWaitingForChatInput[client])
		{
			char SID[64];
			GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

			if (text[strlen(text)-1] == '"')
			{
				text[strlen(text)-1] = '\0';
			}

			strcopy(g_sReceivedChatInput[client], sizeof(g_sReceivedChatInput[]), text[1]);
			g_bWaitingForChatInput[client] = false;
			ReplaceString(g_sReceivedChatInput[client], sizeof(g_sReceivedChatInput), "\"", "'");

			if (StrEqual(g_sInputType[client], "ChangeTag"))
			{
				if (SetTag(SID, g_sReceivedChatInput[client], client))
				{
					CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}tag{default} to: {green}%s{default}", g_sReceivedChatInput[client]);
				}
			}
			else if (StrEqual(g_sInputType[client], "ColorTag"))
			{
				if (IsSource2009() && IsValidHex(g_sReceivedChatInput[client]))
				{
					if (SetColor(SID, "tagcolor", g_sReceivedChatInput[client], client))
					{
						if (g_sReceivedChatInput[client][0] != '#')
							Format(g_sReceivedChatInput[client], sizeof(g_sReceivedChatInput[]), "#%s", g_sReceivedChatInput[client]);
						CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}tag color{default} to: \x07%s%s", g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
					}
				}
				else if (!IsSource2009())
				{
					StringMap smTrie = MC_GetTrie();
					char value[32];
					if (smTrie.GetString(g_sReceivedChatInput[client], value, sizeof(value)) && SetColor(SID, "tagcolor", g_sReceivedChatInput[client], client))
						CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}tag color{default} to: {%s}%s{default}!", g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
					else
						CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid color name given.");
				}
				else
				{
					CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid HEX Color code given.");
				}
			}
			else if (StrEqual(g_sInputType[client], "ColorName"))
			{
				if (IsSource2009() && IsValidHex(g_sReceivedChatInput[client]))
				{
					if (SetColor(SID, "namecolor", g_sReceivedChatInput[client], client))
					{
						if (g_sReceivedChatInput[client][0] != '#')
							Format(g_sReceivedChatInput[client], sizeof(g_sReceivedChatInput[]), "#%s", g_sReceivedChatInput[client]);
						CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}name color{default} to: \x07%s%s", g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
					}
				}
				else if (!IsSource2009())
				{
					StringMap smTrie = MC_GetTrie();
					char value[32];
					if (smTrie.GetString(g_sReceivedChatInput[client], value, sizeof(value)) && SetColor(SID, "namecolor", g_sReceivedChatInput[client], client))
						CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}name color{default} to: {%s}%s{default}!", g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
					else
						CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid color name given.");
				}
				else
				{
					CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid HEX Color code given.");
				}
			}
			else if (StrEqual(g_sInputType[client], "ColorText"))
			{
				if (IsValidHex(g_sReceivedChatInput[client]))
				{
					if (SetColor(SID, "textcolor", g_sReceivedChatInput[client], client))
					{
						if (g_sReceivedChatInput[client][0] != '#')
							Format(g_sReceivedChatInput[client], sizeof(g_sReceivedChatInput[]), "#%s", g_sReceivedChatInput[client]);
						CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}text color{default} to: \x07%s%s{default}!", g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
					}
				}
				else if (!IsSource2009())
				{
					StringMap smTrie = MC_GetTrie();
					char value[32];
					if (smTrie.GetString(g_sReceivedChatInput[client], value, sizeof(value)) && SetColor(SID, "textcolor", g_sReceivedChatInput[client], client))
						CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}text color{default} to: {%s}%s{default}!", g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
					else
						CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid color name given.");
				}
				else
				{
					CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid HEX Color code given.");
				}
			}
			else if (StrEqual(g_sInputType[client], "MenuForceTag"))
			{
				if (SetTag(g_sATargetSID[client], g_sReceivedChatInput[client], client, true))
				{
					CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} tag to: {green}%s{default}!", g_iATarget[client], g_sReceivedChatInput[client]);
				}
			}
			else if (StrEqual(g_sInputType[client], "MenuForceTagColor"))
			{
				if (IsValidHex(g_sReceivedChatInput[client]))
				{
					if (SetColor(g_sATargetSID[client], "tagcolor", g_sReceivedChatInput[client], client, true))
					{
						if (g_sReceivedChatInput[client][0] == '#' && IsSource2009())
						{
							ReplaceString(g_sReceivedChatInput[client], sizeof(g_sReceivedChatInput[]), "#", "");
							CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} tag color to: \x07%s#%s{default}!", g_iATarget[client], g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
						}
						else
							CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} tag color to: {%s}%s{default}!", g_iATarget[client], g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
					}
				}
				else
				{
					CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Invalid HEX Color code given.");
				}
			}
			else if (StrEqual(g_sInputType[client], "MenuForceNameColor"))
			{
				if (IsValidHex(g_sReceivedChatInput[client]))
				{
					if (SetColor(g_sATargetSID[client], "namecolor", g_sReceivedChatInput[client], client, true))
					{
						if (g_sReceivedChatInput[client][0] == '#' && IsSource2009())
						{
							ReplaceString(g_sReceivedChatInput[client], sizeof(g_sReceivedChatInput[]), "#", "");
							CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} name color to: \x07%s#%s{default}!", g_iATarget[client], g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
						}
						else
							CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} name color to: {%s}%s{default}!", g_iATarget[client], g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
					}
				}
				else
				{
					CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Invalid HEX Color code given.");
				}
			}
			else if (StrEqual(g_sInputType[client], "MenuForceTextColor"))
			{
				if (IsValidHex(g_sReceivedChatInput[client]))
				{
					if (SetColor(g_sATargetSID[client], "textcolor", g_sReceivedChatInput[client], client, true))
					{
						if (g_sReceivedChatInput[client][0] == '#' && IsSource2009())
						{
							ReplaceString(g_sReceivedChatInput[client], sizeof(g_sReceivedChatInput[]), "#", "");
							CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} text color to: \x07%s#%s{default}!", g_iATarget[client], g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
						}
						else
							CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Successfully set {green}%N's{default} text color to: {%s}%s{default}!", g_iATarget[client], g_sReceivedChatInput[client], g_sReceivedChatInput[client]);
					}
				}
				else
				{
					CPrintToChat(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Invalid HEX Color code given.");
				}
			}

			return Plugin_Handled;
		}
		else
		{
			if (StrEqual(command, "say_team", false))
				g_msgIsTeammate = true;
			else
				g_msgIsTeammate = false;
		}
	}

	return Plugin_Continue;
}

////////////////////////////////////////////
//Force Tag                            /////
////////////////////////////////////////////

public Action Command_ForceTag(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_forcetag <name|#userid|@filter> <tag text>");
		return Plugin_Handled;
	}

	int iTarget;
	char sTarget[64];
	char sTag[64];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	GetCmdArg(2, sTag, sizeof(sTag));

	if ((iTarget = FindTarget(client, sTarget, true)) == -1)
	{
		return Plugin_Handled;
	}

	char SID[64];
	GetClientAuthId(iTarget, AuthId_Steam2, SID, sizeof(SID));

	SetTag(SID, sTag, client, true);

	return Plugin_Handled;
}

////////////////////////////////////////////
//Force Tag Color                      /////
////////////////////////////////////////////

public Action Command_ForceTagColor(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_forcetagcolor <name|#userid|@filter> <RRGGBB HEX|0-255 0-255 0-255 RGB CODE>");
		return Plugin_Handled;
	}

	ForceColor(client, "tagcolor");

	return Plugin_Handled;
}

////////////////////////////////////////////
//Force Name Color                     /////
////////////////////////////////////////////

public Action Command_ForceNameColor(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_forcenamecolor <name|#userid|@filter> <RRGGBB HEX|0-255 0-255 0-255 RGB CODE>");
		return Plugin_Handled;
	}

	ForceColor(client, "namecolor");

	return Plugin_Handled;
}

////////////////////////////////////////////
//Force Text Color                     /////
////////////////////////////////////////////

public Action Command_ForceTextColor(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_forcetextcolor <name|#userid|@filter> <RRGGBB HEX|0-255 0-255 0-255 RGB CODE>");
		return Plugin_Handled;
	}

	ForceColor(client, "textcolor");

	return Plugin_Handled;
}

////////////////////////////////////////////
//Reset Tag & Colors                   /////
////////////////////////////////////////////

public Action Command_CCCReset(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_cccreset <name|#userid|@filter>");
		return Plugin_Handled;
	}

	int iTarget;
	char sTarget[64];
	GetCmdArg(1, sTarget, sizeof(sTarget));

	if ((iTarget = FindTarget(client, sTarget, true)) == -1)
	{
		return Plugin_Handled;
	}

	char SID[64];
	GetClientAuthId(iTarget, AuthId_Steam2, SID, sizeof(SID));

	CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Cleared {green}%N's tag {default}&{green} colors{default}.", iTarget);
	RemoveCCC(SID, iTarget);

	return Plugin_Handled;
}

////////////////////////////////////////////
//Ban Tag & Color Changes              /////
////////////////////////////////////////////

public Action Command_CCCBan(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_cccban <name|#userid|@filter> <optional:time>");
		return Plugin_Handled;
	}

	int iTarget;
	char sTarget[64];
	char sTime[128];
	GetCmdArg(1, sTarget, sizeof(sTarget));

	if (args > 1)
	{
		GetCmdArg(2, sTime, sizeof(sTime));
	}

	if ((iTarget = FindTarget(client, sTarget, true)) == -1)
	{
		return Plugin_Handled;
	}

	char SID[64];
	GetClientAuthId(iTarget, AuthId_Steam2, SID, sizeof(SID));

	BanCCC(SID, client, iTarget, sTime);

	return Plugin_Handled;
}

////////////////////////////////////////////
//Allow Tag & Color Changes            /////
////////////////////////////////////////////

public Action Command_CCCUnban(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_cccunban <name|#userid|@filter>");
		return Plugin_Handled;
	}

	int iTarget;
	char sTarget[64];
	GetCmdArg(1, sTarget, sizeof(sTarget));

	if ((iTarget = FindTarget(client, sTarget, true)) == -1)
	{
		return Plugin_Handled;
	}

	char SID[64];
	GetClientAuthId(iTarget, AuthId_Steam2, SID, sizeof(SID));

	UnBanCCC(SID, client, iTarget);

	return Plugin_Handled;
}

////////////////////////////////////////////
//Set Tag                              /////
////////////////////////////////////////////

public Action Command_SetTag(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[CCC] Cannot use command from server console");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_tag <tag text>");
		Menu_Main(client);
		return Plugin_Handled;
	}

	char SID[64];
	char arg[64];
	GetCmdArgString(arg, sizeof(arg));
	GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

	ReplaceString(arg, sizeof(arg), "\"", "'");

	if (SetTag(SID, arg, client))
	{
		CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}tag{default} to: {green}%s{default}", arg);
	}

	return Plugin_Handled;
}

////////////////////////////////////////////
//Clear Tag                            /////
////////////////////////////////////////////

public Action Command_ClearTag(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[CCC] Cannot use command from server console");
		return Plugin_Handled;
	}

	char SID[64];
	GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

	SetTag(SID, "", client);

	return Plugin_Handled;
}

////////////////////////////////////////////
//Set Tag Color                        /////
////////////////////////////////////////////

public Action Command_SetTagColor(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[CCC] Cannot use command from server console");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		PrintToChat(client, "[SM] Usage: sm_tagcolor <RRGGBB HEX|0-255 0-255 0-255 RGB CODE>");
		Menu_TagPrefs(client);
		return Plugin_Handled;
	}

	char SID[64];
	char col[64];
	GetCmdArg(1, col, sizeof(col));
	GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

	if (IsValidRGBNum(col))
	{
		char g[8];
		char b[8];
		GetCmdArg(2, g, sizeof(g));
		GetCmdArg(3, b, sizeof(b));
		int hex;
		hex |= ((StringToInt(col) & 0xFF) << 16);
		hex |= ((StringToInt(g) & 0xFF) << 8);
		hex |= ((StringToInt(b) & 0xFF) << 0);

		Format(col, 64, "%06X", hex);
	}

	if (IsValidHex(col))
	{
		if (SetColor(SID, "tagcolor", col, client))
		{
			if (col[0] == '#' && IsSource2009())
			{
				ReplaceString(col, sizeof(col), "#", "");
				CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}tag color{default} to: \x07%s#%s", col, col);
			}
			else
			{
				CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}tag color{default} to: {%s}%s", col, col);
			}
		}
	}
	else
	{
		CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid HEX|RGB color code given.");
	}

	return Plugin_Handled;
}

////////////////////////////////////////////
//Clear Tag Color                      /////
////////////////////////////////////////////

public Action Command_ClearTagColor(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[CCC] Cannot use command from server console");
		return Plugin_Handled;
	}

	char SID[64];
	GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

	SetColor(SID, "tagcolor", "", client);

	return Plugin_Handled;
}

////////////////////////////////////////////
//Set Name Color                       /////
////////////////////////////////////////////

public Action Command_SetNameColor(int client, int args)
{
	if (!client)
	{
		PrintToServer("[CCC] Cannot use command from server console");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		PrintToChat(client, "[SM] Usage: sm_namecolor <RRGGBB HEX|0-255 0-255 0-255 RGB CODE>");
		Menu_NameColor(client);
		return Plugin_Handled;
	}

	char SID[64];
	char col[64];
	GetCmdArg(1, col, sizeof(col));
	GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

	if (IsValidRGBNum(col))
	{
		char g[8];
		char b[8];
		GetCmdArg(2, g, sizeof(g));
		GetCmdArg(3, b, sizeof(b));
		int hex;
		hex |= ((StringToInt(col) & 0xFF) << 16);
		hex |= ((StringToInt(g) & 0xFF) << 8);
		hex |= ((StringToInt(b) & 0xFF) << 0);

		Format(col, 64, "%06X", hex);
	}

	if (IsValidHex(col))
	{
		if (SetColor(SID, "namecolor", col, client))
		{
			if (col[0] == '#' && IsSource2009())
			{
				ReplaceString(col, sizeof(col), "#", "");
				CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}name color{default} to: \x07%s#%s", col, col);
			}
			else
			{
				CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}name color{default} to: {%s}%s", col, col);
			}
		}
	}
	else
	{
		CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid HEX|RGB color code given.");
	}

	return Plugin_Handled;
}

////////////////////////////////////////////
//Clear Name Color                     /////
////////////////////////////////////////////

public Action Command_ClearNameColor(int client, int args)
{
	if (!client)
	{
		PrintToServer("[CCC] Cannot use command from server console");
		return Plugin_Handled;
	}

	char SID[64];
	GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

	SetColor(SID, "namecolor", "", client);

	return Plugin_Handled;
}

////////////////////////////////////////////
//Set Text Color                       /////
////////////////////////////////////////////

public Action Command_SetTextColor(int client, int args)
{
	if (!client)
	{
		PrintToServer("[CCC] Cannot use command from server console");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		PrintToChat(client, "[SM] Usage: sm_textcolor <RRGGBB HEX|0-255 0-255 0-255 RGB CODE>");
		Menu_ChatColor(client);
		return Plugin_Handled;
	}

	char SID[64];
	char col[64];
	GetCmdArg(1, col, sizeof(col));
	GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

	if (IsValidRGBNum(col))
	{
		char g[8];
		char b[8];
		GetCmdArg(2, g, sizeof(g));
		GetCmdArg(3, b, sizeof(b));
		int hex;
		hex |= ((StringToInt(col) & 0xFF) << 16);
		hex |= ((StringToInt(g) & 0xFF) << 8);
		hex |= ((StringToInt(b) & 0xFF) << 0);

		Format(col, 64, "%06X", hex);
	}

	if (IsValidHex(col))
	{
		if (SetColor(SID, "textcolor", col, client))
		{
			if (col[0] == '#' && IsSource2009())
			{
				ReplaceString(col, sizeof(col), "#", "");
				CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}text color{default} to: \x07%s#%s", col, col);
			}
			else
			{
				CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}text color{default} to: {%s}%s", col, col);
			}
		}
	}
	else
	{
		CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} Invalid HEX|RGB color code given.");
	}

	return Plugin_Handled;
}

////////////////////////////////////////////
//Clear Text Color                     /////
////////////////////////////////////////////

public Action Command_ClearTextColor(int client, int args)
{
	if (!client)
	{
		PrintToServer("[CCC] Cannot use command from server console");
		return Plugin_Handled;
	}

	char SID[64];
	GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

	SetColor(SID, "textcolor", "", client);

	return Plugin_Handled;
}

public Action Command_ToggleTag(int client, int args)
{
	if (!client)
	{
		PrintToServer("[CCC] Cannot use command from server console");
		return Plugin_Handled;
	}

	char SID[64];
	GetClientAuthId(client, AuthId_Steam2, SID, sizeof(SID));

	ToggleCCC(SID, client);
	CReplyToCommand(client, "{green}[{red}C{green}C{blue}C{green}]{default} {green}Tag and color{default} displaying %s", g_iClientEnable[client] ? "{red}enabled{default}." : "{green}disabled{default}.");

	return Plugin_Handled;
}

//  888b     d888 8888888888 888b    888 888     888
//  8888b   d8888 888        8888b   888 888     888
//  88888b.d88888 888        88888b  888 888     888
//  888Y88888P888 8888888    888Y88b 888 888     888
//  888 Y888P 888 888        888 Y88b888 888     888
//  888  Y8P  888 888        888  Y88888 888     888
//  888   "   888 888        888   Y8888 Y88b. .d88P
//  888       888 8888888888 888    Y888  "Y88888P"

/* public Handle_Commands(Handle menu, TopMenuAction action, TopMenuObject:object_id, param1, char buffer[], maxlength)
{
		if (action == TopMenuAction_DisplayOption)
		{
			Format(buffer, maxlength, "%s", "CCC Commands", param1);
		}
		else if (action == TopMenuAction_DisplayTitle)
		{
			Format(buffer, maxlength, "%s", "CCC Commands:", param1);
		}
		else if (action == TopMenuAction_SelectOption)
		{
			PrintToChat(param1, "ur gay");
		}
}

public Handle_AMenuReset(Handle menu, TopMenuAction action, TopMenuObject:object_id, param1, char buffer[], maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Reset", param1);
	}
	else if(action == TopMenuAction_SelectOption)
	{
		new Handle MenuAReset = CreateMenu(MenuHandler_AdminReset);
		SetMenuTitle(MenuAReset, "Select a Target (Reset Tag/Colors)");
		SetMenuExitBackButton(MenuAReset, true);

		AddTargetsToMenu2(MenuAReset, 0, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

		DisplayMenu(MenuAReset, param1, MENU_TIME_FOREVER);
	}
}

public Handle_AMenuBan(Handle menu, TopMenuAction action, TopMenuObject:object_id, param1, char buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Ban", param1);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		new Handle MenuABan = CreateMenu(MenuHandler_AdminBan);
		SetMenuTitle(MenuABan, "Select a Target (Ban from Tag/Colors)");
		SetMenuExitBackButton(MenuABan, true);

		AddTargetsToMenu2(MenuABan, 0, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

		DisplayMenu(MenuABan, param1, MENU_TIME_FOREVER);
	}
}

public Handle_AMenuUnBan(Handle menu, TopMenuAction action, TopMenuObject:object_id, param1, char buffer[], maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Unban", param1);
	}
	else if(action == TopMenuAction_SelectOption)
	{
		AdminMenu_UnBanList(param1);
	}
} */

public void AdminMenu_UnBanList(int client)
{
	Menu MenuAUnBan = new Menu(MenuHandler_AdminUnBan);
	MenuAUnBan.SetTitle("Select a Target (Unban from Tag/Colors)");
	MenuAUnBan.ExitBackButton = true;

	int clients = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientBanned(i))
		{
			char info[64];
			char id[32];
			int remaining;
			remaining = ((g_iClientBanned[client] - GetTime()) / 60);

			if (g_iClientBanned[client] == 0)
			{
				Format(info, sizeof(info), "%N (Permanent)", i);
			}
			else
			{
				Format(info, sizeof(info), "%N (%d minutes remaining)", i, remaining);
			}

			Format(id, sizeof(id), "%i", GetClientUserId(i));

			MenuAUnBan.AddItem(id, info);

			clients++;
		}
	}

	if (!clients)
	{
		char sBuffer[64];
		Format(sBuffer, sizeof(sBuffer), "No banned clients");
		MenuAUnBan.AddItem("0", sBuffer, ITEMDRAW_DISABLED);
	}

	MenuAUnBan.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_AdminUnBan(Menu MenuAUnBan, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuAUnBan);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Admin(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		char SID[64];
		MenuAUnBan.GetItem(param2, Selected, sizeof(Selected));
		int target;
		int userid = StringToInt(Selected);
		target = GetClientOfUserId(userid);

		if (!target)
		{
			CReplyToCommand(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Player no longer available.");

			/*if (g_hAdminMenu != null)
			{
				DisplayTopMenu(g_hAdminMenu, param1, TopMenuPosition_LastCategory);
			}*/
			Menu_Admin(param1);
		}
		else
		{
			GetClientAuthId(target, AuthId_Steam2, SID, sizeof(SID));

			UnBanCCC(SID, param1, target);

			/*if (g_hAdminMenu != null)
			{
				DisplayTopMenu(g_hAdminMenu, param1, TopMenuPosition_LastCategory);
				return;
			}*/
		}

		Menu_Admin(param1);
	}

	return 0;
}

public void Menu_Main(int client)
{
	if (IsVoteInProgress())
		return;

	Menu MenuMain = new Menu(MenuHandler_Main);
	MenuMain.SetTitle("Chat Tags & Colors");

	MenuMain.AddItem("Current", "View Current Settings");
	MenuMain.AddItem("Tag", "Tag Options");
	MenuMain.AddItem("Name", "Name Options");
	MenuMain.AddItem("Chat", "Chat Options");

	char sBuffer[128];
	Format(sBuffer, sizeof(sBuffer), "Colors and tag: %s", g_iClientEnable[client] ? "Enabled" : "Disabled");
	MenuMain.AddItem("CCC", sBuffer);

	if (g_bWaitingForChatInput[client])
	{
		MenuMain.AddItem("CancelCInput", "Cancel Chat Input");
	}

	if (HasFlag(client, Admin_Slay) || HasFlag(client, Admin_Cheats))
	{
		MenuMain.AddItem("", "", ITEMDRAW_SPACER);
		MenuMain.AddItem("Admin", "Administrative Options");
	}

	MenuMain.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Main(Menu MenuMain, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		if (param1 != MenuEnd_Selected)
			delete MenuMain;
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		GetMenuItem(MenuMain, param2, Selected, sizeof(Selected));

		if (StrEqual(Selected, "Tag"))
		{
			Menu_TagPrefs(param1);
		}
		else if (StrEqual(Selected, "Name"))
		{
			Menu_NameColor(param1);
		}
		else if (StrEqual(Selected, "Chat"))
		{
			Menu_ChatColor(param1);
		}
		else if (StrEqual(Selected, "CCC"))
		{
			char sClientSteamID[64];
			GetClientAuthId(param1, AuthId_Steam2, sClientSteamID, sizeof(sClientSteamID));

			ToggleCCC(sClientSteamID, param1);
			CloseHandle(MenuMain);
			Menu_Main(param1);
		}
		else if (StrEqual(Selected, "Admin"))
		{
			Menu_Admin(param1);
		}
		else if (StrEqual(Selected, "CancelCInput"))
		{
			g_bWaitingForChatInput[param1] = false;
			g_sInputType[param1] = "";
			Menu_Main(param1);
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Cancelled chat input.");
		}
		else if (StrEqual(Selected, "Current"))
		{
			char sTagF[64];
			char sTagColorF[64];
			char sNameColorF[64];
			char sChatColorF[64];

			Menu hMenuCurrent = new Menu(MenuHandler_Current);
			hMenuCurrent.SetTitle("Current Settings:");
			hMenuCurrent.ExitBackButton = true;

			Format(sTagF, sizeof(sTagF), "Current Tag: %s", g_sClientTag[param1]);
			Format(sTagColorF, sizeof(sTagColorF), "Current Tag Color: %s", g_sClientTagColor[param1]);
			Format(sNameColorF, sizeof(sNameColorF), "Current Name Color: %s", g_sClientNameColor[param1]);
			Format(sChatColorF, sizeof(sChatColorF), "Current Chat Color: %s", g_sClientChatColor[param1]);

			hMenuCurrent.AddItem("sTag", sTagF, ITEMDRAW_DISABLED);
			hMenuCurrent.AddItem("sTagColor", sTagColorF, ITEMDRAW_DISABLED);
			hMenuCurrent.AddItem("sNameColor", sNameColorF, ITEMDRAW_DISABLED);
			hMenuCurrent.AddItem("sChatColor", sChatColorF, ITEMDRAW_DISABLED);

			hMenuCurrent.Display(param1, MENU_TIME_FOREVER);
		}
		else
		{
			PrintToChat(param1, "congrats you broke it");
		}
	}

	return 0;
}

public int MenuHandler_Current(Menu hMenuCurrent, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(hMenuCurrent);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Main(param1);
		return 0;
	}

	return 0;
}

public void Menu_Admin(int client)
{
	if (IsVoteInProgress())
		return;

	Menu MenuAdmin = new Menu(MenuHandler_Admin);
	MenuAdmin.SetTitle("Chat Tags & Colors Admin");
	MenuAdmin.ExitBackButton = true;

	MenuAdmin.AddItem("Reset", "Reset a client's Tag & Colors");
	MenuAdmin.AddItem("Ban", "Ban a client from the Tag & Colors system");
	MenuAdmin.AddItem("Unban", "Unban a client from the Tag & Colors system");

	if (HasFlag(client, Admin_Cheats))
	{
		MenuAdmin.AddItem("ForceTag", "Forcefully change a client's Tag");
		MenuAdmin.AddItem("ForceTagColor", "Forcefully change a client's Tag Color");
		MenuAdmin.AddItem("ForceNameColor", "Forcefully change a client's Name Color");
		MenuAdmin.AddItem("ForceTextColor", "Forcefully change a client's Chat Color");
	}

	MenuAdmin.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Admin(Menu MenuAdmin, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuAdmin);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Main(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		MenuAdmin.GetItem(param2, Selected, sizeof(Selected));

		if (StrEqual(Selected, "Reset"))
		{
			Menu MenuAReset = new Menu(MenuHandler_AdminReset);
			MenuAReset.SetTitle("Select a Target (Reset Tag/Colors)");
			MenuAReset.ExitBackButton = true;

			AddTargetsToMenu2(MenuAReset, 0, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

			MenuAReset.Display(param1, MENU_TIME_FOREVER);
			return 0;
		}
		else if (StrEqual(Selected, "Ban"))
		{
			Menu MenuABan = new Menu(MenuHandler_AdminBan);
			MenuABan.SetTitle("Select a Target (Ban from Tag/Colors)");
			MenuABan.ExitBackButton = true;

			AddTargetsToMenu2(MenuABan, 0, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

			MenuABan.Display(param1, MENU_TIME_FOREVER);
			return 0;
		}
		else if (StrEqual(Selected, "Unban"))
		{
			AdminMenu_UnBanList(param1);
			return 0;
		}
		else if (StrEqual(Selected, "ForceTag"))
		{
			Menu MenuAFTag = new Menu(MenuHandler_AdminForceTag);
			MenuAFTag.SetTitle("Select a Target (Force Tag)");
			MenuAFTag.ExitBackButton = true;

			AddTargetsToMenu2(MenuAFTag, 0, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

			MenuAFTag.Display(param1, MENU_TIME_FOREVER);
			return 0;
		}
		else if (StrEqual(Selected, "ForceTagColor"))
		{
			Menu MenuAFTColor = new Menu(MenuHandler_AdminForceTagColor);
			MenuAFTColor.SetTitle("Select a Target (Force Tag Color)");
			MenuAFTColor.ExitBackButton = true;

			AddTargetsToMenu2(MenuAFTColor, 0, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

			MenuAFTColor.Display(param1, MENU_TIME_FOREVER);
			return 0;
		}
		else if (StrEqual(Selected, "ForceNameColor"))
		{
			Menu MenuAFNColor = new Menu(MenuHandler_AdminForceNameColor);
			MenuAFNColor.SetTitle("Select a Target (Force Name Color)");
			MenuAFNColor.ExitBackButton = true;

			AddTargetsToMenu2(MenuAFNColor, 0, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

			MenuAFNColor.Display(param1, MENU_TIME_FOREVER);
			return 0;
		}
		else if (StrEqual(Selected, "ForceTextColor"))
		{
			Menu MenuAFTeColor = new Menu(MenuHandler_AdminForceTextColor);
			MenuAFTeColor.SetTitle("Select a Target (Force Text Color)");
			MenuAFTeColor.ExitBackButton = true;

			AddTargetsToMenu2(MenuAFTeColor, 0, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

			MenuAFTeColor.Display(param1, MENU_TIME_FOREVER);
			return 0;
		}
		else if (StrEqual(Selected, "CancelCInput"))
		{
			g_bWaitingForChatInput[param1] = false;
			g_sInputType[param1] = "";
			Menu_Admin(param1);
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Cancelled chat input.");
		}
		else
		{
			PrintToChat(param1, "congrats you broke it");
		}

		Menu_Admin(param1);
	}

	return 0;
}

public int MenuHandler_AdminReset(Menu MenuAReset, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuAReset);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Admin(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		char SID[64];
		MenuAReset.GetItem(param2, Selected, sizeof(Selected));
		int target;
		int userid = StringToInt(Selected);
		target = GetClientOfUserId(userid);

		if (!target)
		{
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Player no longer available.");

			/*if (g_hAdminMenu != null)
			{
				DisplayTopMenu(g_hAdminMenu, param1, TopMenuPosition_LastCategory);
				return;
			}*/
			Menu_Admin(param1);
		}
		else
		{
			GetClientAuthId(target, AuthId_Steam2, SID, sizeof(SID));

			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Cleared {green}%N's tag {default}&{green} colors{default}.", target);
			RemoveCCC(SID, target);
		}

		Menu_Admin(param1);
	}

	return 0;
}

public int MenuHandler_AdminBan(Menu MenuABan, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuABan);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Admin(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		char SID[64];
		MenuABan.GetItem(param2, Selected, sizeof(Selected));
		int target;
		int userid = StringToInt(Selected);
		target = GetClientOfUserId(userid);

		if (!target)
		{
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Player no longer available.");

			/*if (g_hAdminMenu != null)
			{
				DisplayTopMenu(g_hAdminMenu, param1, TopMenuPosition_LastCategory);
				return;
			}*/
			Menu_Admin(param1);
		}
		else
		{
			GetClientAuthId(target, AuthId_Steam2, SID, sizeof(SID));
			g_iATarget[param1] = target;
			g_sATargetSID[param1] = SID;

			Menu MenuABTime = new Menu(MenuHandler_AdminBanTime);
			MenuABTime.SetTitle("Select Ban Length");
			MenuABTime.ExitBackButton = true;

			MenuABTime.AddItem("10", "10 Minutes");
			MenuABTime.AddItem("30", "30 Minutes");
			MenuABTime.AddItem("60", "1 Hour");
			MenuABTime.AddItem("1440", "1 Day");
			MenuABTime.AddItem("10080", "1 Week");
			MenuABTime.AddItem("40320", "1 Month");
			MenuABTime.AddItem("0", "Permanent");

			MenuABTime.Display(param1, MENU_TIME_FOREVER);
		}
	}

	return 0;
}

public int MenuHandler_AdminBanTime(Menu MenuABTime, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuABTime);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu MenuABan = new Menu(MenuHandler_AdminBan);
		MenuABan.SetTitle("Select a Target (Ban from Tag/Colors)");
		MenuABan.ExitBackButton = true;

		AddTargetsToMenu2(MenuABan, 0, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

		MenuABan.Display(param1, MENU_TIME_FOREVER);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[128];
		MenuABTime.GetItem(param2, Selected, sizeof(Selected));

		if (!g_iATarget[param1])
		{
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Player no longer available.");

			/*if (g_hAdminMenu != null)
			{
				DisplayTopMenu(g_hAdminMenu, param1, TopMenuPosition_LastCategory);
				return;
			}*/

			Menu_Admin(param1);
		}

		BanCCC(g_sATargetSID[param1], param1, g_iATarget[param1], Selected);

		/*if (g_hAdminMenu != null)
		{
			DisplayTopMenu(g_hAdminMenu, param1, TopMenuPosition_LastCategory);
			return;
		}*/

		Menu_Admin(param1);
	}

	return 0;
}

public int MenuHandler_AdminForceTag(Menu MenuAFTag, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuAFTag);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Admin(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		char SID[64];
		MenuAFTag.GetItem(param2, Selected, sizeof(Selected));
		int target;
		int userid = StringToInt(Selected);
		target = GetClientOfUserId(userid);

		if (!target)
		{
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Player no longer available.");
			Menu_Admin(param1);
		}
		else
		{
			GetClientAuthId(target, AuthId_Steam2, SID, sizeof(SID));
			g_iATarget[param1] = target;
			g_sATargetSID[param1] = SID;
			g_bWaitingForChatInput[param1] = true;
			g_sInputType[param1] = "MenuForceTag";
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Please enter what you want {green}%N's{default} tag to be.", target);
		}

		Menu_Admin(param1);
	}

	return 0;
}

public int MenuHandler_AdminForceTagColor(Menu MenuAFTColor, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuAFTColor);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Admin(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		MenuAFTColor.GetItem(param2, Selected, sizeof(Selected));
		int target;
		int userid = StringToInt(Selected);

		target = GetClientOfUserId(userid);

		if (!target)
		{
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Player no longer available.");
			Menu_Admin(param1);
		}
		else
		{
			char SID[64];
			GetClientAuthId(target, AuthId_Steam2, SID, sizeof(SID));

			g_iATarget[param1] = target;
			g_sATargetSID[param1] = SID;
			g_bWaitingForChatInput[param1] = true;
			g_sInputType[param1] = "MenuForceTagColor";

			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Please enter what you want {green}%N's{default} tag color to be (#{red}RR{green}GG{blue}BB{default} HEX only!).", target);
		}

		Menu_Admin(param1);
	}

	return 0;
}

public int MenuHandler_AdminForceNameColor(Menu MenuAFNColor, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuAFNColor);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Admin(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		char SID[64];
		MenuAFNColor.GetItem(param2, Selected, sizeof(Selected));
		int target;
		int userid = StringToInt(Selected);
		target = GetClientOfUserId(userid);

		if (!target)
		{
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Player no longer available.");
			Menu_Admin(param1);
		}
		else
		{
			GetClientAuthId(target, AuthId_Steam2, SID, sizeof(SID));
			g_iATarget[param1] = target;
			g_sATargetSID[param1] = SID;
			g_bWaitingForChatInput[param1] = true;
			g_sInputType[param1] = "MenuForceNameColor";
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Please enter what you want {green}%N's{default} name color to be (#{red}RR{green}GG{blue}BB{default} HEX only!).", target);
		}

		Menu_Admin(param1);
	}

	return 0;
}

public int MenuHandler_AdminForceTextColor(Menu MenuAFTeColor, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuAFTeColor);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Admin(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		char SID[64];
		MenuAFTeColor.GetItem(param2, Selected, sizeof(Selected));
		int target;
		int userid = StringToInt(Selected);
		target = GetClientOfUserId(userid);

		if (!target)
		{
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Player no longer available.");
			Menu_Admin(param1);
		}
		else
		{
			GetClientAuthId(target, AuthId_Steam2, SID, sizeof(SID));
			g_iATarget[param1] = target;
			g_sATargetSID[param1] = SID;
			g_bWaitingForChatInput[param1] = true;
			g_sInputType[param1] = "MenuForceTextColor";
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}-ADMIN]{default} Please enter what you want {green}%N's{default} text color to be (#{red}RR{green}GG{blue}BB{default} HEX only!).", target);
		}

		Menu_Admin(param1);
	}

	return 0;
}

public void Menu_TagPrefs(int client)
{
	if (IsVoteInProgress())
		return;

	Menu MenuTPrefs = new Menu(MenuHandler_TagPrefs);
	MenuTPrefs.SetTitle("Tag Options:");
	MenuTPrefs.ExitBackButton = true;

	MenuTPrefs.AddItem("Reset", "Clear Tag");
	MenuTPrefs.AddItem("ResetColor", "Clear Tag Color");
	MenuTPrefs.AddItem("ChangeTag", "Change Tag (Chat input)");
	MenuTPrefs.AddItem("Color", "Change Tag Color");
	MenuTPrefs.AddItem("ColorTag", "Change Tag Color (Chat input)");

	MenuTPrefs.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_TagPrefs(Menu MenuTPrefs, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuTPrefs);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Main(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		MenuTPrefs.GetItem(param2, Selected, sizeof(Selected));

		if (StrEqual(Selected, "Reset"))
		{
			char SID[64];
			GetClientAuthId(param1, AuthId_Steam2, SID, sizeof(SID));

			SetTag(SID, "", param1);

			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Cleared your custom {green}tag{default}.");
		}
		else if (StrEqual(Selected, "ResetColor"))
		{
			char SID[64];
			GetClientAuthId(param1, AuthId_Steam2, SID, sizeof(SID));

			if (SetColor(SID, "tagcolor", "", param1))
				CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Cleared your custom {green}tag color{default}.");
		}
		else if (StrEqual(Selected, "ChangeTag"))
		{
			g_bWaitingForChatInput[param1] = true;
			g_sInputType[param1] = "ChangeTag";
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Please enter what you want your {green}tag{default} to be.");
		}
		else if (StrEqual(Selected, "ColorTag"))
		{
			g_bWaitingForChatInput[param1] = true;
			g_sInputType[param1] = "ColorTag";
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Please enter what you want your {green}tag color{default} to be (#{red}RR{green}GG{blue}BB{default} HEX only!).");
		}
		else
		{
			Menu ColorsMenu = new Menu(MenuHandler_TagColorSub);
			char info[64];
			ColorsMenu.SetTitle("Pick a color:");
			ColorsMenu.ExitBackButton = true;

			StringMap smTrie = MC_GetTrie();
			if (smTrie!= null && g_sColorsArray != null)
			{
				for (int i = 0; i < g_sColorsArray.Length; i++)
				{
					char key[64];
					char value[64];
					g_sColorsArray.GetString(i, key, sizeof(key));
					smTrie.GetString(key, value, sizeof(value));
					Format(info, sizeof(info), "%s (%s)", key, value);
					ColorsMenu.AddItem(key, info);
				}
			}

			ColorsMenu.Display(param1, MENU_TIME_FOREVER);
			return 0;
		}

		Menu_Main(param1);
	}

	return 0;
}

public void Menu_NameColor(int client)
{
	if (IsVoteInProgress())
		return;

	Menu MenuNColor = new Menu(MenuHandler_NameColor);
	MenuNColor.SetTitle("Name Options:");
	MenuNColor.ExitBackButton = true;

	MenuNColor.AddItem("ResetColor", "Clear Name Color");
	MenuNColor.AddItem("Color", "Change Name Color");
	MenuNColor.AddItem("ColorName", "Change Name Color (Chat input)");

	MenuNColor.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_NameColor(Menu MenuNColor, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuNColor);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Main(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		MenuNColor.GetItem(param2, Selected, sizeof(Selected));

		if (StrEqual(Selected, "ResetColor"))
		{
			char SID[64];
			GetClientAuthId(param1, AuthId_Steam2, SID, sizeof(SID));

			if (SetColor(SID, "namecolor", "", param1))
				CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Cleared your custom {green}name color{default}.");
		}
		else if (StrEqual(Selected, "ColorName"))
		{
			g_bWaitingForChatInput[param1] = true;
			g_sInputType[param1] = "ColorName";
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Please enter what you want your {green}name color{default} to be (#{red}RR{green}GG{blue}BB{default} HEX only!).");
		}
		else
		{
			Menu ColorsMenu = new Menu(MenuHandler_NameColorSub);
			char info[64];
			char SID[64];
			GetClientAuthId(param1, AuthId_Steam2, SID, sizeof(SID));
			ColorsMenu.SetTitle("Pick a color:");
			ColorsMenu.ExitBackButton = true;

			StringMap smTrie = MC_GetTrie();
			if (smTrie!= null && g_sColorsArray != null)
			{
				for (int i = 0; i < g_sColorsArray.Length; i++)
				{
					char key[64];
					char value[64];
					g_sColorsArray.GetString(i, key, sizeof(key));
					smTrie.GetString(key, value, sizeof(value));
					Format(info, sizeof(info), "%s (%s)", key, value);
					ColorsMenu.AddItem(key, info);
				}
			}

			if (HasFlag(param1, Admin_Cheats))
			{
				ColorsMenu.AddItem("X", "X");
			}

			ColorsMenu.Display(param1, MENU_TIME_FOREVER);
			return 0;
		}

		Menu_Main(param1);
	}

	return 0;
}

public void Menu_ChatColor(int client)
{
	if (IsVoteInProgress())
		return;

	Menu MenuCColor = new Menu(MenuHandler_ChatColor);
	MenuCColor.SetTitle("Chat Options:");
	MenuCColor.ExitBackButton = true;

	MenuCColor.AddItem("ResetColor", "Clear Chat Text Color");
	MenuCColor.AddItem("Color", "Change Chat Text Color");
	MenuCColor.AddItem("ColorText", "Change Chat Text Color (Chat input)");

	MenuCColor.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ChatColor(Menu MenuCColor, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuCColor);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_Main(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char Selected[32];
		MenuCColor.GetItem(param2, Selected, sizeof(Selected));

		if (StrEqual(Selected, "ResetColor"))
		{
			char SID[64];
			GetClientAuthId(param1, AuthId_Steam2, SID, sizeof(SID));

			if (SetColor(SID, "textcolor", "", param1))
				CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Cleared your custom {green}text color{default}.");
		}
		else if (StrEqual(Selected, "ColorText"))
		{
			g_bWaitingForChatInput[param1] = true;
			g_sInputType[param1] = "ColorText";
			CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Please enter what you want your {green}text color{default} to be (#{red}RR{green}GG{blue}BB{default} HEX only!).");
		}
		else
		{
			Menu ColorsMenu = new Menu(MenuHandler_ChatColorSub);
			char info[64];
			ColorsMenu.SetTitle("Pick a color:");
			ColorsMenu.ExitBackButton = true;

			StringMap smTrie = MC_GetTrie();
			if (smTrie!= null && g_sColorsArray != null)
			{
				for (int i = 0; i < g_sColorsArray.Length; i++)
				{
					char key[64];
					char value[64];
					g_sColorsArray.GetString(i, key, sizeof(key));
					smTrie.GetString(key, value, sizeof(value));
					Format(info, sizeof(info), "%s (%s)", key, value);
					ColorsMenu.AddItem(key, info);
				}
			}

			ColorsMenu.Display(param1, MENU_TIME_FOREVER);
			return 0;
		}

		Menu_Main(param1);
	}

	return 0;
}

public int MenuHandler_TagColorSub(Menu MenuTCSub, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuTCSub);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_TagPrefs(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char SID[64];
		char Selected[64];
		MenuTCSub.GetItem(param2, Selected, sizeof(Selected));
		GetClientAuthId(param1, AuthId_Steam2, SID, sizeof(SID));

		if (SetColor(SID, "tagcolor", Selected, param1))
		{
			if (Selected[0] == '#' && IsSource2009())
			{
				ReplaceString(Selected, sizeof(Selected), "#", "");
				CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}tag color{default} to: \x07%s#%s", Selected, Selected);
			}
			else
				CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}tag color{default} to: {%s}%s", Selected, Selected);
		}

		Menu_TagPrefs(param1);
	}

	return 0;
}

public int MenuHandler_NameColorSub(Menu MenuNCSub, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuNCSub);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_NameColor(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char SID[64];
		char Selected[64];
		MenuNCSub.GetItem(param2, Selected, sizeof(Selected));
		GetClientAuthId(param1, AuthId_Steam2, SID, sizeof(SID));

		if (SetColor(SID, "namecolor", Selected, param1))
		{
			if (Selected[0] == '#' && IsSource2009())
			{
				ReplaceString(Selected, sizeof(Selected), "#", "");
				CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}name color{default} to: \x07%s#%s", Selected, Selected);
			}
			else
				CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}name color{default} to: {%s}%s", Selected, Selected);
		}

		Menu_NameColor(param1);
	}

	return 0;
}

public int MenuHandler_ChatColorSub(Menu MenuCCSub, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		CloseHandle(MenuCCSub);
		return 0;
	}

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Menu_ChatColor(param1);
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char SID[64];
		char Selected[64];
		MenuCCSub.GetItem(param2, Selected, sizeof(Selected));
		GetClientAuthId(param1, AuthId_Steam2, SID, sizeof(SID));

		if (SetColor(SID, "textcolor", Selected, param1))
		{
			if (Selected[0] == '#' && IsSource2009())
			{
				ReplaceString(Selected, sizeof(Selected), "#", "");
				CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}text color{default} to: \x07%s#%s", Selected, Selected);
			}
			else
				CPrintToChat(param1, "{green}[{red}C{green}C{blue}C{green}]{default} Successfully set your {green}text color{default} to: {%s}%s", Selected, Selected);
		}

		Menu_ChatColor(param1);
	}

	return 0;
}

//  88888888888     d8888  .d8888b.        .d8888b.  8888888888 88888888888 88888888888 8888888 888b    888  .d8888b.
//      888        d88888 d88P  Y88b      d88P  Y88b 888            888         888       888   8888b   888 d88P  Y88b
//      888       d88P888 888    888      Y88b.      888            888         888       888   88888b  888 888    888
//      888      d88P 888 888              "Y888b.   8888888        888         888       888   888Y88b 888 888
//      888     d88P  888 888  88888          "Y88b. 888            888         888       888   888 Y88b888 888  88888
//      888    d88P   888 888    888            "888 888            888         888       888   888  Y88888 888    888
//      888   d8888888888 Y88b  d88P      Y88b  d88P 888            888         888       888   888   Y8888 Y88b  d88P
//      888  d88P     888  "Y8888P88       "Y8888P"  8888888888     888         888     8888888 888    Y888  "Y8888P88

stock void ClearValues(int client)
{
	g_iClientEnable[client] = 1;
	Format(g_sClientTag[client], sizeof(g_sClientTag[]), "");
	Format(g_sClientTagColor[client], sizeof(g_sClientTagColor[]), "");
	Format(g_sClientNameColor[client], sizeof(g_sClientNameColor[]), "");
	Format(g_sClientChatColor[client], sizeof(g_sClientChatColor[]), "");

	g_iDefaultClientEnable[client] = 1;
	Format(g_sDefaultClientTag[client], sizeof(g_sDefaultClientTag[]), "");
	Format(g_sDefaultClientTagColor[client], sizeof(g_sDefaultClientTagColor[]), "");
	Format(g_sDefaultClientNameColor[client], sizeof(g_sDefaultClientNameColor[]), "");
	Format(g_sDefaultClientChatColor[client], sizeof(g_sDefaultClientChatColor[]), "");
}

stock void ResetClient(int client)
{
	Format(g_sReceivedChatInput[client], sizeof(g_sReceivedChatInput[]), "");
	Format(g_sInputType[client], sizeof(g_sInputType[]), "");
	Format(g_sATargetSID[client], sizeof(g_sATargetSID[]), "");
	g_bWaitingForChatInput[client] = false;
	g_iATarget[client] = 0;
	g_sClientSID[client] = "";
	ClearValues(client);
}

public Action Hook_UserMessage(UserMsg msg_id, Handle bf, const players[], int playersNum, bool reliable, bool init)
{
	char sAuthorTag[64];

	if (g_bProto)
	{
		g_msgAuthor = PbReadInt(bf, "ent_idx");
		g_msgIsChat = PbReadBool(bf, "chat");
		PbReadString(bf, "msg_name", g_msgName, sizeof(g_msgName));
		PbReadString(bf, "params", g_msgSender, sizeof(g_msgSender), 0);
		PbReadString(bf, "params", g_msgText, sizeof(g_msgText), 1);
	}
	else
	{
		g_msgAuthor = BfReadByte(bf);
		g_msgIsChat = view_as<bool>(BfReadByte(bf));
		BfReadString(bf, g_msgName, sizeof(g_msgName), false);
		BfReadString(bf, g_msgSender, sizeof(g_msgSender), false);
		BfReadString(bf, g_msgText, sizeof(g_msgText), false);
	}

	LogError("ent_idx %d, chat %d, msg_name %s, msgSender %s, msgText %s", g_msgAuthor, g_msgIsChat, g_msgName, g_msgSender, g_msgText);

	if (strlen(g_msgName) == 0 || strlen(g_msgSender) == 0)
		return Plugin_Continue;

	if (!strcmp(g_msgName, "#Cstrike_Name_Change"))
		return Plugin_Continue;

	TrimString(g_msgText);

	if (strlen(g_msgText) == 0)
		return Plugin_Handled;

	CCC_GetTag(g_msgAuthor, sAuthorTag, sizeof(sAuthorTag));

	bool bIsAction;
	char sNameColor[32];
	char sChatColor[32];
	char sTagColor[32];
	bool bNameAlpha = CCC_GetColor(g_msgAuthor, view_as<CCC_ColorType>(CCC_NameColor), sNameColor);
	bool bChatAlpha = CCC_GetColor(g_msgAuthor, view_as<CCC_ColorType>(CCC_ChatColor), sChatColor);
	bool bTagAlpha = CCC_GetColor(g_msgAuthor, view_as<CCC_ColorType>(CCC_TagColor), sTagColor);

	if (!strncmp(g_msgText, "/me", 3, false))
	{
		strcopy(g_msgName, sizeof(g_msgName), "Cstrike_Chat_Me");
		strcopy(g_msgText, sizeof(g_msgText), g_msgText[4]);
		bIsAction = true;
	}

	if (GetConVarInt(g_cvar_ReplaceText) > 0)
	{
		char sPart[MAX_CHAT_LENGTH];
		char sBuff[MAX_CHAT_LENGTH];
		int CurrentIndex = 0;
		int NextIndex = 0;

		while (NextIndex != -1 && CurrentIndex < sizeof(g_msgText))
		{
			NextIndex = BreakString(g_msgText[CurrentIndex], sPart, sizeof(sPart));

			sBuff = "";
			for (int i = 0; i < g_iReplaceListSize; i++)
			{
				if (StrEqual(g_sReplaceList[i][0], sPart))
				{
					Format(sBuff, sizeof(sBuff), "%s", g_sReplaceList[i][1]);
					break;
				}
			}

			if(sBuff[0])
			{
				ReplaceString(g_msgText[CurrentIndex], sizeof(g_msgText) - CurrentIndex, sPart, sBuff);
				CurrentIndex += strlen(sBuff);
			}
			else
				CurrentIndex += NextIndex;
		}
	}

	if (!g_msgAuthor || HasFlag(g_msgAuthor, Admin_Generic) || HasFlag(g_msgAuthor, Admin_Custom1))
	{
		CFormatColor(g_msgText, sizeof(g_msgText), g_msgAuthor);
	}

	StringMap smTrie = MC_GetTrie();
	char value[32];

	if (!bIsAction && g_iClientEnable[g_msgAuthor])
	{
		if (bNameAlpha)
		{
			int hexColor = StringToInt(sNameColor, 16);
			Format(g_msgSender, sizeof(g_msgSender), "\x07%06X%s", hexColor, g_msgSender);
		}
		else
		{
			Format(g_msgSender, sizeof(g_msgSender), "%s%s", sNameColor, g_msgSender);
		}

		if (strlen(sAuthorTag) > 0)
		{
			LogError("MsgName: %s, TagColor: %stest, AuthorTag: %s, g_msgSender: %s", g_msgName, sTagColor, sAuthorTag, g_msgSender);
			if (bTagAlpha)
			{
				int hexColor = StringToInt(sTagColor, 16);
				Format(g_msgSender, sizeof(g_msgSender), "\x07%06X%s%s", hexColor, sAuthorTag, g_msgSender);
			}
			else
			{
				Format(g_msgSender, sizeof(g_msgSender), "%s%s%s", sTagColor, sAuthorTag, g_msgSender);
			}
		}

		if (g_msgText[0] == '>' && GetConVarInt(g_cvar_GreenText) > 0 && smTrie.GetString("green", value, sizeof(value)))
		{
			Format(g_msgText, sizeof(g_msgText), "%s%s", value, g_msgText);
		}

		if (bChatAlpha)
		{
			int hexColor = StringToInt(sChatColor, 16);
			Format(g_msgText, sizeof(g_msgText), "\x07%06X%s", hexColor, g_msgText);
		}
		else
		{
			Format(g_msgText, sizeof(g_msgText), "%s%s", sChatColor, g_msgText);
		}
	}

	Format(g_msgFinal, sizeof(g_msgFinal), "%t", g_msgName, g_msgSender, g_msgText);

	LogError("Final msg: %s", g_msgFinal);

	return Plugin_Handled;
}

public Action Event_PlayerSay(Handle event, const char[] name, bool dontBroadcast)
{
	if (g_msgAuthor == -1 || GetClientOfUserId(GetEventInt(event, "userid")) != g_msgAuthor)
	{
		return;
	}

	if (strlen(g_msgText) == 0)
		return;

	int[] players = new int[MaxClients + 1];
	int playersNum = 0;

	if (g_msgIsTeammate && g_msgAuthor > 0)
	{
		int team = GetClientTeam(g_msgAuthor);

		for (int client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client) && GetClientTeam(client) == team)
			{
				if(!g_Ignored[client * (MAXPLAYERS + 1) + g_msgAuthor])
					players[playersNum++] = client;
			}
		}
	}
	else
	{
		for (int client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client))
			{
				if(!g_Ignored[client * (MAXPLAYERS + 1) + g_msgAuthor])
					players[playersNum++] = client;
			}
		}
	}

	if (!playersNum)
	{
		g_msgAuthor = -1;
		return;
	}

	Handle SayText2 = StartMessage("SayText2", players, playersNum, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS);

	if (g_bProto)
	{
		PbSetInt(SayText2, "ent_idx", g_msgAuthor);
		PbSetBool(SayText2, "chat", g_msgIsChat);
		PbSetString(SayText2, "msg_name", g_msgFinal);
		PbAddString(SayText2, "params", "");
		PbAddString(SayText2, "params", "");
		PbAddString(SayText2, "params", "");
		PbAddString(SayText2, "params", "");
		EndMessage();
	}
	else
	{
		BfWriteByte(SayText2, g_msgAuthor);
		BfWriteByte(SayText2, g_msgIsChat);
		BfWriteString(SayText2, g_msgFinal);
		EndMessage();
	}

	g_msgAuthor = -1;
}

//  888b    888        d8888 88888888888 8888888 888     888 8888888888 .d8888b.
//  8888b   888       d88888     888       888   888     888 888       d88P  Y88b
//  88888b  888      d88P888     888       888   888     888 888       Y88b.
//  888Y88b 888     d88P 888     888       888   Y88b   d88P 8888888    "Y888b.
//  888 Y88b888    d88P  888     888       888    Y88b d88P  888           "Y88b.
//  888  Y88888   d88P   888     888       888     Y88o88P   888             "888
//  888   Y8888  d8888888888     888       888      Y888P    888       Y88b  d88P
//  888    Y888 d88P     888     888     8888888     Y8P     8888888888 "Y8888P"

stock bool CheckForward(int author, const char[] message, CCC_ColorType type)
{
	new Action result = Plugin_Continue;

	Call_StartForward(applicationForward);
	Call_PushCell(author);
	Call_PushString(message);
	Call_PushCell(type);
	Call_Finish(result);

	if (result >= Plugin_Handled)
		return false;

	// Compatibility
	switch(type)
	{
		case CCC_TagColor: return TagForward(author);
		case CCC_NameColor: return NameForward(author);
		case CCC_ChatColor: return ColorForward(author);
	}

	return true;
}

stock bool ColorForward(int author)
{
	Action result = Plugin_Continue;

	Call_StartForward(colorForward);
	Call_PushCell(author);
	Call_Finish(result);

	if (result >= Plugin_Handled)
		return false;

	return true;
}

stock bool NameForward(int author)
{
	Action result = Plugin_Continue;

	Call_StartForward(nameForward);
	Call_PushCell(author);
	Call_Finish(result);

	if (result >= Plugin_Handled)
		return false;

	return true;
}

stock bool TagForward(int author)
{
	Action result = Plugin_Continue;

	Call_StartForward(tagForward);
	Call_PushCell(author);
	Call_Finish(result);

	if (result >= Plugin_Handled)
		return false;

	return true;
}

stock bool ConfigForward(int client)
{
	Action myresult = Plugin_Continue;

	Call_StartForward(preLoadedForward);
	Call_PushCell(client);
	Call_Finish(myresult);

	if (myresult >= Plugin_Handled)
		return false;

	return true;
}

public int Native_GetColor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!client || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return false;
	}

	StringMap smTrie = MC_GetTrie();
	char value[32] = "";

	switch(GetNativeCell(2))
	{
		case CCC_TagColor:
		{
			if (StrEqual(g_sClientTagColor[client], "T", false))
			{
				smTrie.GetString("teamcolor", value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else if (StrEqual(g_sClientTagColor[client], "G", false))
			{
				smTrie.GetString("green", value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else if (StrEqual(g_sClientTagColor[client], "O", false))
			{
				smTrie.GetString("olive", value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else if (IsSource2009() && (strlen(g_sClientTagColor[client]) == 6 || strlen(g_sClientTagColor[client]) == 8))
			{
				SetNativeString(3, g_sClientTagColor[client], sizeof(g_sClientTagColor[]));
				return true;
			}
			else if (smTrie.GetString(g_sClientTagColor[client], value, sizeof(value)))
			{
				smTrie.GetString(g_sClientTagColor[client], value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else
			{
				SetNativeString(3, value, sizeof(value));
				return false;
			}
		}

		case CCC_NameColor:
		{
			if (StrEqual(g_sClientNameColor[client], "G", false))
			{
				smTrie.GetString("green", value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else if (StrEqual(g_sClientNameColor[client], "X", false))
			{
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else if (StrEqual(g_sClientNameColor[client], "O", false))
			{
				smTrie.GetString("olive", value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else if (IsSource2009() && (strlen(g_sClientNameColor[client]) == 6 || strlen(g_sClientNameColor[client]) == 8))
			{
				SetNativeString(3, g_sClientNameColor[client], sizeof(g_sClientNameColor[]));
				return true;
			}
			else if (smTrie.GetString(g_sClientNameColor[client], value, sizeof(value)))
			{
				smTrie.GetString(g_sClientNameColor[client], value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else
			{
				SetNativeString(3, value, sizeof(value));
				return false;
			}
		}

		case CCC_ChatColor:
		{
			if (StrEqual(g_sClientChatColor[client], "T", false))
			{
				smTrie.GetString("teamcolor", value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else if (StrEqual(g_sClientChatColor[client], "G", false))
			{
				smTrie.GetString("green", value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else if (StrEqual(g_sClientChatColor[client], "O", false))
			{
				smTrie.GetString("olive", value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else if (IsSource2009() && (strlen(g_sClientChatColor[client]) == 6 || strlen(g_sClientChatColor[client]) == 8))
			{
				SetNativeString(3, g_sClientChatColor[client], sizeof(g_sClientChatColor[]));
				return true;
			}
			else if (smTrie.GetString(g_sClientChatColor[client], value, sizeof(value)))
			{
				smTrie.GetString(g_sClientChatColor[client], value, sizeof(value));
				SetNativeString(3, value, sizeof(value));
				return false;
			}
			else
			{
				SetNativeString(3, value, sizeof(value));
				return false;
			}
		}
	}

	return false;
}

public int Native_SetColor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!client || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return 0;
	}

	char color[32];

	if (GetNativeCell(3) < 0)
	{
		switch (GetNativeCell(3))
		{
			case COLOR_CGREEN:
			{
				Format(color, sizeof(color), "G");
			}
			case COLOR_OLIVE:
			{
				Format(color, sizeof(color), "O");
			}
			case COLOR_TEAM:
			{
				Format(color, sizeof(color), "T");
			}
			case COLOR_NULL:
			{
				Format(color, sizeof(color), "X");
			}
			case COLOR_NONE:
			{
				Format(color, sizeof(color), "");
			}
		}
	}
	else
	{
		if (!GetNativeCell(4))
		{
			// No alpha
			Format(color, sizeof(color), "%06X", GetNativeCell(3));
		}
		else
		{
			// Alpha specified
			Format(color, sizeof(color), "%08X", GetNativeCell(3));
		}
	}

	if (strlen(color) != 6 && strlen(color) != 8 && !StrEqual(color, "G", false) && !StrEqual(color, "O", false) && !StrEqual(color, "T", false) && !StrEqual(color, "X", false))
	{
		return 0;
	}

	switch (GetNativeCell(2))
	{
		case CCC_TagColor:
		{
			strcopy(g_sClientTagColor[client], sizeof(g_sClientTagColor[]), color);
		}
		case CCC_NameColor:
		{
			strcopy(g_sClientNameColor[client], sizeof(g_sClientNameColor[]), color);
		}
		case CCC_ChatColor:
		{
			strcopy(g_sClientChatColor[client], sizeof(g_sClientChatColor[]), color);
		}
	}

	return 1;
}

public int Native_GetTag(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!client || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return 0;
	}

	SetNativeString(2, g_sClientTag[client], GetNativeCell(3));
	return 1;
}

public int Native_SetTag(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!client || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return 0;
	}

	GetNativeString(2, g_sClientTag[client], sizeof(g_sClientTag[]));
	return 1;
}

public int Native_ResetColor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!client || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return 0;
	}

	switch(GetNativeCell(2))
	{
		case CCC_TagColor:
		{
			strcopy(g_sClientTagColor[client], sizeof(g_sClientTagColor[]), g_sDefaultClientTagColor[client]);
		}
		case CCC_NameColor:
		{
			strcopy(g_sClientNameColor[client], sizeof(g_sClientNameColor[]), g_sDefaultClientNameColor[client]);
		}
		case CCC_ChatColor:
		{
			strcopy(g_sClientChatColor[client], sizeof(g_sClientChatColor[]), g_sDefaultClientChatColor[client]);
		}
	}

	return 1;
}

public int Native_ResetTag(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!client || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return 0;
	}

	strcopy(g_sClientTag[client], sizeof(g_sClientTag[]), g_sDefaultClientTag[client]);
	return 1;
}

public int Native_UpdateIgnoredArray(Handle plugin, int numParams)
{
	GetNativeArray(1, g_Ignored, sizeof(g_Ignored));

	return 1;
}

public int Native_UnLoadClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!client || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return 0;
	}
	OnClientDisconnect(client);
	return 1;
}

public int Native_LoadClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!client || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return 0;
	}
	OnClientPostAdminCheck(client);
	return 1;
}

public int Native_ReloadConfig(Handle plugin, int numParams)
{
	LateLoad();
	return 1;
}