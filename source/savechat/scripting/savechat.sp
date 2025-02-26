#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <geoip>
#include <log4sp>	// requires log4sp 1.8.0+

#define TEAM_UNASSIGNED 0
#define TEAM_SPECTATOR 1
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define LOGGER_NAME "savechat"
#define CONFIG_PATH "configs/savechat.cfg"

ConVar g_hHostport = null;
bool g_bIsIdling[MAXPLAYERS + 1] = { false, ... };
Logger g_hLogger = null;

#define PLUGIN_VERSION "r1.5.1"	// 1.3 reworked.

public Plugin myinfo = 
{
	name = "[Any] SaveChat",	// yeah sure it is any, but im lazy to change the team name so you might need to change it yourself >.<
	author = "citkabuto, sorallll, blueblur",	/* Extentsion: Log for SourcePawn by F1F88*/
	description = "Records player chat messages to a file",
	version = PLUGIN_VERSION,
	url = "https://github.com/blueblur0730/modified-plugins"
}

public void OnPluginStart()
{
	CreateConVar("sm_savechat_version", PLUGIN_VERSION, "Plugin version", FCVAR_DONTRECORD | FCVAR_NOTIFY);
	g_hHostport = FindConVar("hostport");

	g_hLogger = CreateLoggerOrFailed(LOGGER_NAME);
	g_hLogger.SetLevel(LogLevel_Info);
	g_hLogger.SetPattern("[%Y-%m-%d %H:%M:%S.%e] [%n] %v");
	g_hLogger.Info("--- [Any] SaveChat "...PLUGIN_VERSION..." Loaded. ---");
	g_hLogger.Flush();
	g_hLogger.FlushOn(LogLevel_Info);

	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
	HookEvent("player_bot_replace", Event_OnSwitchIdling, EventHookMode_Post);	// go idle
	HookEvent("bot_player_replace", Event_OnSwitchIdling, EventHookMode_Post);	// leave idle

	char sPath[128];
	KeyValues kv = new KeyValues("Commands");
	BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_PATH);
	if (kv.ImportFromFile(sPath))
	{
		int count = 1;
		char sCommand[64];
		if (kv.GotoFirstSubKey(false))
		{
			do
			{
				kv.GetString(NULL_STRING, sCommand, sizeof(sCommand));
				AddCommandListener(CommandListener, sCommand);
				count++;
			}
			while (kv.GotoNextKey(false));
		}
	}
	else
	{
		delete kv;
		delete g_hLogger;
		SetFailState("Failed to load config file \""...CONFIG_PATH..."\".");
	}

	delete kv;
}

public void OnPluginEnd()
{
	if (g_hLogger) delete g_hLogger;
}

public void OnMapStart()
{
	if (!g_hLogger) g_hLogger = CreateLoggerOrFailed(LOGGER_NAME);
	StartOrEndPhrase(true);
}

public void OnMapEnd()
{
	StartOrEndPhrase(false);
}

void StartOrEndPhrase(bool bMapStatus)
{
	char sMap[128];
	GetCurrentMap(sMap, sizeof(sMap));

	g_hLogger.Info("--=================================================================--");
	g_hLogger.InfoAmxTpl("--- %s: %s ---", bMapStatus ? "Map Started" : "Map Ended", sMap);
	g_hLogger.Info("--=================================================================--");
}

public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client))
		return;

	char sCountry[3];
	char sPlayerIP[32];

	if (!GetClientIP(client, sPlayerIP, sizeof(sPlayerIP), true)) 
		strcopy(sCountry, sizeof(sCountry), "N/A");
	else 
	{
		if (!GeoipCode2(sPlayerIP, sCountry)) 
			strcopy(sCountry, sizeof(sCountry), "N/A");
	}

	g_hLogger.InfoAmxTpl("---[%s] %L Joined the Game (%s)---", sCountry, client, sPlayerIP);
}

Action CommandListener(int client, char[] command, int argc)
{
	if (client > MaxClients)
		return Plugin_Continue;

	if (client > 0 && !IsClientInGame(client))
		return Plugin_Continue;

	static char sTeamName[12];
	static char sMessage[255];

	if (client > 0 && !g_bIsIdling[client]) 
		GetTeamNameEx(GetClientTeam(client), sTeamName, sizeof(sTeamName));

	GetCmdArgString(sMessage, sizeof(sMessage));
	StripQuotes(sMessage);

	g_hLogger.InfoAmxTpl("[%s] %N: [%s] %s",
			!client ? "Console" : (g_bIsIdling[client] ? "Idle" : sTeamName),
			client,
			command,
			sMessage);

	return Plugin_Continue;
}

void Event_OnSwitchIdling(Event hEvent, const char[] name, bool dontBroadcast)
{
	bool bBotReplaced = (!strncmp(name, "b", 1));
	int replacee = bBotReplaced ? GetClientOfUserId(hEvent.GetInt("bot")) : GetClientOfUserId(hEvent.GetInt("player"));
	int replacer = bBotReplaced ? GetClientOfUserId(hEvent.GetInt("player")) : GetClientOfUserId(hEvent.GetInt("bot"));

	if (replacee <= 0 || replacee > MaxClients)
		return;

	if (replacer <= 0 || replacer > MaxClients)
		return;

	if (!IsClientInGame(replacee) || !IsClientInGame(replacer))
		return;

	bBotReplaced ? (g_bIsIdling[replacer] = false) : (g_bIsIdling[replacee] = true);
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	RoundStartedOrEnded(false);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	RoundStartedOrEnded(true);
}

void RoundStartedOrEnded(bool bRound)
{
	char sMap[255];
	GetCurrentMap(sMap, sizeof(sMap));

	g_hLogger.Info("--=================================================================--");
	g_hLogger.InfoAmxTpl("--- %s: %s ---", bRound ? "Round Started" : "Round Ended", sMap);
	g_hLogger.Info("--=================================================================--");
}

void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients || IsFakeClient(client))
		return;

	char sMessage[255];
	event.GetString("reason", sMessage, sizeof(sMessage));
	g_hLogger.InfoAmxTpl("---%L Left the game (reason: %s)---", client, sMessage);
}

void GetTeamNameEx(int team, char[] szName, int iMaxLen)
{
	switch (team)
	{
		case TEAM_UNASSIGNED:
			strcopy(szName, iMaxLen, "Unassigned");
		case TEAM_SPECTATOR:
			strcopy(szName, iMaxLen, "Spectator");
		case TEAM_SURVIVOR:
			strcopy(szName, iMaxLen, "Survivor");
		case TEAM_INFECTED:
			strcopy(szName, iMaxLen, "Infected");
	}
}

Logger CreateLoggerOrFailed(const char[] name)
{
	Logger logger = Logger.Get(name);

	if (!logger)	// if not exist, create new one.
	{
		char path[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, path, sizeof(path), "logs/savechat/savechat[%%d-%%m-%%y].log");
		logger = DailyFileSink.CreateLogger(LOGGER_NAME, path, _, _, _, _, DailyFilePortCalculator);
		if (!logger) SetFailState("Failed to create log file.");
	}

	return logger;
}

void DailyFilePortCalculator(char[] filename, int maxlen, int sec)
{
	char buffer[PLATFORM_MAX_PATH];
	int extIndex = FindCharInString(filename, '.', true);

	// no valid extension found
	if (extIndex <= 0 || extIndex == strlen(filename) - 1)
	{
		FormatEx(buffer, sizeof(buffer), "%s-port[%d]", filename, g_hHostport.IntValue);
		FormatTime(filename, maxlen, buffer, sec);
		return;
	}

	// treat cases like "/etc/rc.d/somelogfile or "/abc/.hiddenfile"
	int folderIndex = FindCharInString(filename, '/', true);
	if (folderIndex == -1)
		folderIndex = FindCharInString(filename, '\\', true);

	if (folderIndex != -1 && folderIndex >= extIndex - 1)
	{
		FormatEx(buffer, sizeof(buffer), "%s-port[%d]", filename, g_hHostport.IntValue);
		FormatTime(filename, maxlen, buffer, sec);
		return;
	}

	filename[extIndex] = '\0';
	FormatEx(buffer, sizeof(buffer), "%s-port[%d].%s", filename, g_hHostport.IntValue, filename[extIndex + 1]);
	FormatTime(filename, maxlen, buffer, sec);
}
