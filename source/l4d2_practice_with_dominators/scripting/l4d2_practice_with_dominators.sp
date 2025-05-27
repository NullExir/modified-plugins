#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <l4d2util>
#include <colors>

#define PLUGIN_VERSION		 "2.3"

//#define GAMEDATA_FILE		 "l4d2_practice_with_dominators"
#define TRANSLATION_FILE	 "l4d2_practice_with_dominators.phrases"
//#define DETOUR_FUNCTION	 "CTerrorPlayer::IsDominatedBySpecialInfected"
//#define SDKCALL_FUNCTION	 "CTerrorPlayer::GetSpecialInfectedDominatingMe"
#define DEBUG				 0

#define TAUNT_HIGH_THRESHOLD 0.4
#define TAUNT_MID_THRESHOLD	 0.2
#define TAUNT_LOW_THRESHOLD	 0.04
#define DEPLOY_ANIM_TIME	 0.9667	// 29 frame / 30 fps, basically applied to all guns.

enum SIType
{
	SIType_Smoker = 1,
	SIType_Boomer,
	SIType_Hunter,
	SIType_Spitter,
	SIType_Jockey,
	SIType_Charger,
	SIType_Witch,
	SIType_Tank,

	SIType_Size	   // 8 size
}

static const char SINames[SIType_Size][] = {
	"",
	"gas",			// smoker
	"exploding",	// boomer
	"hunter",
	"spitter",
	"jockey",
	"charger",
	"witch",
	"tank",
};

ConVar
	g_hCvar_Enable,
	g_hCvar_DmgDone,
	g_hCvar_ShouldDoDamage,
	g_hCvar_ShouldPassToHook,
	g_hCvar_ShouldChargerDieOnCarry,
	g_hCvar_ShouldTaunt,
	g_hCvar_ShouldQuickStandUp,
	g_hCvar_ShouldQuickSwitchWeapon,
	g_hCvar_ShouldBlockNormalAttack;

bool
	g_bEnable,
	g_bShouldDoDamage,
	g_bShouldPassToHook,
	g_bShouldChargerDieOnCarry,
	g_bShouldTaunt,
	g_bShouldQuickStandUp,
	g_bShouldQuickSwitchWeapon,
	g_bShouldBlockNormalAttack;

float
	g_flDmgDone;

bool g_bIsHooked[MAXPLAYERS + 1]		= { false, ... };
bool g_bIsDominated[MAXPLAYERS + 1]		= { false, ... };
bool g_bLateHook						= false;

public Plugin myinfo =
{
	name = "[L4D2] Practice With Dominators",
	author = "blueblur, 东, Blade + Confogl Team, Tabun, Visor",
	description = "Fight against dominators in a pure way.",
	version	= PLUGIN_VERSION,
	url	= "https://github.com/blueblur0730/modified-plugins"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if (test != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	g_bLateHook = late;

	RegPluginLibrary("l4d2_practice_with_dominators");
	return APLRes_Success;
}

public void OnPluginStart()
{
	//IniGameData();
	LoadTranslation(TRANSLATION_FILE);
	CreateConVar("l4d2_practice_with_dominators_version", PLUGIN_VERSION, "The version of Practice With Dominators plugin", FCVAR_NOTIFY | FCVAR_DEVELOPMENTONLY);

	g_hCvar_Enable					= CreateConVar("pwd_enable", "1", "Enable or disable this plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvar_DmgDone					= CreateConVar("pwd_ability_dmg_done", "24.0", "Damage done from dominator SIs' ability.");
	g_hCvar_ShouldDoDamage			= CreateConVar("pwd_should_do_damage", "1", "Whether dominator SIs should do ability damage or not.", _, true, 0.0, true, 1.0);
	g_hCvar_ShouldPassToHook		= CreateConVar("pwd_should_pass_to_hook", "0", "Whether to pass this plugin's damage to OnTakeDamage hook or not. (To tell other plugins.)", _, true, 0.0, true, 1.0);
	g_hCvar_ShouldChargerDieOnCarry = CreateConVar("pwd_should_charger_die_on_carry", "0", "Whether the charger should be killed or not when carrying a you.", _, true, 0.0, true, 1.0);
	g_hCvar_ShouldTaunt				= CreateConVar("pwd_should_taunt", "1", "Whether to taunt or not", _, true, 0.0, true, 1.0);
	g_hCvar_ShouldQuickStandUp		= CreateConVar("pwd_should_quick_stand_up", "1", "Whether to quick stand up or not", _, true, 0.0, true, 1.0);
	g_hCvar_ShouldQuickSwitchWeapon = CreateConVar("pwd_should_quick_switch_weapon", "1", "Whether to quick switch weapon or not", _, true, 0.0, true, 1.0);
	g_hCvar_ShouldBlockNormalAttack = CreateConVar("pwd_should_block_normal_attack", "1", "Whether to block normal attack or not", _, true, 0.0, true, 1.0);

	g_hCvar_Enable.AddChangeHook(OnConVarChanged);
	g_hCvar_DmgDone.AddChangeHook(OnConVarChanged);
	g_hCvar_ShouldDoDamage.AddChangeHook(OnConVarChanged);
	g_hCvar_ShouldPassToHook.AddChangeHook(OnConVarChanged);
	g_hCvar_ShouldChargerDieOnCarry.AddChangeHook(OnConVarChanged);
	g_hCvar_ShouldTaunt.AddChangeHook(OnConVarChanged);
	g_hCvar_ShouldQuickStandUp.AddChangeHook(OnConVarChanged);
	g_hCvar_ShouldQuickSwitchWeapon.AddChangeHook(OnConVarChanged);
	g_hCvar_ShouldBlockNormalAttack.AddChangeHook(OnConVarChanged);
	OnConVarChanged(null, "", "");
	
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_team", Event_PlayerTeam);
	LateHook();
}

public Action L4D_OnFirstSurvivorLeftSafeArea(int client)
{
	if (!g_bIsHooked[client])
	{
		if (SDKHookEx(client, SDKHook_PostThinkPost, OnPostThinkPost)
			&& SDKHookEx(client, SDKHook_OnTakeDamage, OnTakeDamage))
		{
			g_bIsHooked[client] = true;
		}
	}

	return Plugin_Continue;
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int	 client		   = GetClientOfUserId(event.GetInt("userid"));
	int	 team		   = event.GetInt("team");
	bool bDisconnected = event.GetBool("disconnected");
	bool bIsBot		   = event.GetBool("isbot");

	// ignore bots.
	if (bIsBot && g_bIsHooked[client])
	{
		g_bIsHooked[client] = false;
		return;
	}

	// SDKHook will unhook themselves when hooked client disconnected, we don't need to do anything here.
	if ((!IsClientAndInGame(client) || bDisconnected) && g_bIsHooked[client])
	{
		g_bIsHooked[client] = false;
		return;
	}

	// player swapped away from team survivors, unhook.
	if (team != 2 && g_bIsHooked[client])
	{
		SDKUnhook(client, SDKHook_PostThinkPost, OnPostThinkPost);
		SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		g_bIsHooked[client] = false;
		return;
	}

	// player swapped into team survivors, hook.
	else if (team == 2 && !g_bIsHooked[client])
	{
		if (SDKHookEx(client, SDKHook_PostThinkPost, OnPostThinkPost)
			&& SDKHookEx(client, SDKHook_OnTakeDamage, OnTakeDamage))
		{
			g_bIsHooked[client] = true;
		}
	}
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bIsHooked[i])
			g_bIsHooked[i] = false;

		if (g_bIsDominated[i])
			g_bIsDominated[i] = false;
	}
}

// this cancels get up animation of survivor.
void OnPostThinkPost(int client)
{
	if (IsClientAndInGame(client) && g_bShouldQuickStandUp)
		SetEntPropFloat(client, Prop_Send, "m_flCycle", 1.0);
}

Action OnTakeDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iDamagetype)
{
	if (!g_bEnable)
		return Plugin_Continue;

	if (!IsClientAndInGame(iVictim) || !IsClientAndInGame(iAttacker))
		return Plugin_Continue;

	if (GetClientTeam(iVictim) != L4D2Team_Survivor || GetClientTeam(iAttacker) != L4D2Team_Infected)
		return Plugin_Continue;

	SIType zClass = view_as<SIType>(GetInfectedClass(iAttacker));

#if DEBUG
	PrintToServer("### OnTakeDamage called, victim: %d, attacker: %d, inflictor: %d, damage: %f, damagetype: %d", iVictim, iAttacker, iInflictor, fDamage, iDamagetype);
#endif

	// only block the damage from their ability, more specifically, a DMG_GENERIC damage from this plugin.
	if (zClass == SIType_Charger || zClass == SIType_Jockey || zClass == SIType_Smoker || zClass == SIType_Hunter)
	{
		// should their normal attack damage be blocked?
		if (g_bShouldBlockNormalAttack && (iDamagetype & DMG_CLUB))
		{
			fDamage = 0.0;
			return Plugin_Changed;
		}

		// you are dominated.
		if (!g_bShouldDoDamage && (iDamagetype & DMG_GENERIC) && g_bIsDominated[iVictim])
		{
			fDamage = 0.0;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

// dominators are: hunter, jockey, charger, smoker.
// MRESReturn DTR_CTerrorPlayer_OnIsDominatedBySpecialInfected(int pPlayer, DHookReturn hReturn)
public void L4D2_OnDominatedBySpecialInfected(int victim, int dominator)
{
	if (!g_bEnable)
		return;

	g_bIsDominated[victim] = true;

	// this function also calls on infected. (wth)
	if (!IsClientAndInGame(victim) || GetClientTeam(victim) != L4D2Team_Survivor)
		return;
#if DEBUG
	PrintToServer("### Player %N is dominated.", victim);
	PrintToServer("### Dominator: %d.", dominator);
#endif

	// the domination is done.
	ProcessDomination(dominator, victim);
}

void ProcessDomination(int iAttacker, int iVictim)
{
	int    zClass = GetInfectedClass(iAttacker);
	int	   iRemainingHealth = GetClientHealth(iAttacker);

	bool   bIsBot = false;
	char   sName[MAX_NAME_LENGTH];
	if (IsFakeClient(iAttacker)) bIsBot = true;
	else
	{
		GetClientName(iAttacker, sName, sizeof(sName));
		bIsBot = false;
	}

	CPrintToChatAll("%t", "DamageReport", bIsBot ? "AI" : sName, L4D2_InfectedNames[zClass], iRemainingHealth, g_flDmgDone);

	if (g_bShouldDoDamage)
		SDKHooks_TakeDamage(iVictim, iAttacker, iAttacker, g_flDmgDone, DMG_GENERIC, _, _, _, g_bShouldPassToHook);

	// otherwise you will be carried by 'nothing'
	if (g_bShouldChargerDieOnCarry && view_as<SIType>(zClass) == SIType_Charger && GetEntPropEnt(iVictim, Prop_Send, "m_carryAttacker") != 0)
		L4D2_Charger_EndCarry(iVictim, iAttacker);

	// lastly, kill the infected.
	ForcePlayerSuicide(iAttacker);
	g_bIsDominated[iVictim] = false;

	int iWeapon = GetPlayerWeapon(iVictim);
	CleanGetUp(iVictim, iWeapon);

	if (g_bShouldTaunt)
		DoTaunt(iRemainingHealth, iVictim, zClass);
}

void CleanGetUp(int client, int weapon)
{
	// we are switching weapon anytime, what we want is to cancel the [getup -> switch weapon] this weapon switch anim.
#if DEBUG
	char sName[64];
	GetWeaponName(IdentifyWeapon(weapon), sName, sizeof(sName));
	PrintToServer("### CleanGetUp called when dominated, client: %d, weapon: %d, weapon name: %s", client, weapon, sName);
#endif

	if (!g_bShouldQuickSwitchWeapon)
		return;

	/**
	 * This section is refered to l4d2_smg_reload_tweak by Visor.
	*/
	float oldNextAttack = GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack");
	float newNextAttack = oldNextAttack - DEPLOY_ANIM_TIME + 0.1;
	//float playBackRate	= DEPLOY_ANIM_TIME / 0.1;

#if DEBUG
	PrintToServer("### oldNextAttack: %.1f, newNextAttack: %.1f", oldNextAttack, newNextAttack);
#endif
	if (GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack") != newNextAttack)
	{
#if DEBUG
		PrintToServer("### Setting m_flNextPrimaryAttack");
#endif
		SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", newNextAttack);
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", newNextAttack);
		//SetEntPropFloat(weapon, Prop_Send, "m_flPlaybackRate", playBackRate);	// we cant cancel it. but we can accelerate it.
	}

	/*
		It turns out that may be deploy animation is predicted on client-side.
		But we can still shoot while the deploy animation is still playing.
		so just be it.
	*/
}

void DoTaunt(int iRemainingHealth, int iVictim, int iZclass)
{
	int maxHealth = GetSpecialInfectedHP(iZclass);
	if (!maxHealth)
		return;

	if (iRemainingHealth == 1) CPrintToChat(iVictim, "%t", "Taunt_HP1");
	else if (iRemainingHealth <= RoundToCeil(maxHealth * TAUNT_LOW_THRESHOLD)) CPrintToChat(iVictim, "%t", "Taunt_HPLow");
	else if (iRemainingHealth <= RoundToCeil(maxHealth * TAUNT_MID_THRESHOLD)) CPrintToChat(iVictim, "%t", "Taunt_HPMid");
	else if (iRemainingHealth <= RoundToCeil(maxHealth * TAUNT_HIGH_THRESHOLD)) CPrintToChat(iVictim, "%t", "Taunt_HPHigh");
}

/**
 * ------------------------
 * Stock Functions
 * ------------------------
 */

bool IsClientAndInGame(int client)
{
	return (client > 0 && client < MaxClients && IsClientInGame(client));
}

int GetSpecialInfectedHP(int zClass)
{
	char buffer[32];
	for (int i = 0; i < view_as<int>(SIType_Size); i++)
	{
		if (i != zClass)
			continue;

		Format(buffer, sizeof(buffer), "z_%s_health", SINames[i]);
#if DEBUG
		PrintToServer("### GetSpecialInfectedHP called for %s, health: %d", SINames[i], FindConVar(buffer).IntValue);
#endif
		return FindConVar(buffer).IntValue;
	}

	return 0;
}

int GetPlayerWeapon(int client)
{
	int m_hActiveWeapon = -1;

	if (m_hActiveWeapon == -1) 
		m_hActiveWeapon = FindSendPropInfo("CTerrorPlayer", "m_hActiveWeapon");

	return GetEntDataEnt2(client, m_hActiveWeapon);
}

/*
void IniGameData()
{
	GameData gd = new GameData(GAMEDATA_FILE);
	if (!gd) SetFailState("Failed to load game data \"" ... GAMEDATA_FILE... "\" ");

	DynamicDetour hDetour = DynamicDetour.FromConf(gd, DETOUR_FUNCTION);
	if (!hDetour) SetFailState("Failed to create detour for \"" ... DETOUR_FUNCTION... "\" ");

	if (!hDetour.Enable(Hook_Post, DTR_CTerrorPlayer_OnIsDominatedBySpecialInfected))
		SetFailState("Failed to enable detour for \"" ... DETOUR_FUNCTION... "\" ");

	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(gd, SDKConf_Signature, SDKCALL_FUNCTION))
		SetFailState("Failed to load function from gamedata for \"" ... SDKCALL_FUNCTION... "\" ");

	PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer);
	g_hSDKCall_GetSIDominatingMe = EndPrepSDKCall();
	if (!g_hSDKCall_GetSIDominatingMe)
		SetFailState("Failed to create SDK call for \"" ... SDKCALL_FUNCTION... "\" ");

	delete hDetour;
	delete gd;
}
*/

void LoadTranslation(const char[] translation)
{
	char sPath[PLATFORM_MAX_PATH], sName[64];

	Format(sName, sizeof(sName), "translations/%s.txt", translation);
	BuildPath(Path_SM, sPath, sizeof(sPath), sName);
	if (!FileExists(sPath))
		SetFailState("Missing translation file %s.txt", translation);

	LoadTranslations(translation);
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bEnable = g_hCvar_Enable.BoolValue;
	g_bShouldDoDamage = g_hCvar_ShouldDoDamage.BoolValue;
	g_bShouldPassToHook = g_hCvar_ShouldPassToHook.BoolValue;
	g_bShouldChargerDieOnCarry = g_hCvar_ShouldChargerDieOnCarry.BoolValue;
	g_bShouldTaunt = g_hCvar_ShouldTaunt.BoolValue;
	g_bShouldQuickStandUp = g_hCvar_ShouldQuickStandUp.BoolValue;
	g_bShouldQuickSwitchWeapon = g_hCvar_ShouldQuickSwitchWeapon.BoolValue;
	g_bShouldBlockNormalAttack = g_hCvar_ShouldBlockNormalAttack.BoolValue;

	g_flDmgDone = g_hCvar_DmgDone.FloatValue;
}

void LateHook()
{
	if (g_bLateHook)
	{
		for (int i = 1; i < MaxClients; i++)
		{
			if (!IsClientAndInGame(i))
				continue;

			if (GetClientTeam(i) != L4D2Team_Survivor)
				continue;

			if (SDKHookEx(i, SDKHook_PostThinkPost, OnPostThinkPost)
				&& SDKHookEx(i, SDKHook_OnTakeDamage, OnTakeDamage))
			{
				g_bIsHooked[i] = true;
			}
		}
	}
}