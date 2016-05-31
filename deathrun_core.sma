#include <amxmodx>
#include <cstrike>
#include <engine>
#include <fun>
#include <fakemeta>
#include <hamsandwich>
#include <xs>

#if AMXX_VERSION_NUM < 183
#include <colorchat>
#endif

#define PLUGIN "Deathrun: Core"
#define VERSION "0.6"
#define AUTHOR "Mistrick"

#pragma semicolon 1

#define IsPlayer(%1) (%1 && %1 <= 32)

new const PREFIX[] = "^4[DRM]";

new Trie:g_tRemoveEntities;
new g_iEntBuyZone;
new g_iForwardSpawn, HamHook:g_iHamPreThink;
new g_msgShowMenu, g_msgVGUIMenu, g_msgAmmoPickup, g_msgWeapPickup;

new g_pBlockFallDmg, g_pBlockKill;
new g_pAutoBalance, g_pLimitTeams, g_pSvRestart;

new g_iOldAmmoPickupBlock, g_iOldWeapPickupBlock;

new g_iTerrorist, g_iNextTerrorist;

new g_iMaxPlayers;

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
	
	register_cvar("deathrun_core_version", VERSION, FCVAR_SERVER | FCVAR_SPONLY);
	
	g_pBlockKill = register_cvar("deathrun_block_kill", "1");
	g_pBlockFallDmg = register_cvar("deathrun_block_falldmg", "1");
	
	g_pAutoBalance = get_cvar_pointer("mp_autoteambalance");
	g_pLimitTeams  = get_cvar_pointer("mp_limitteams");
	g_pSvRestart = get_cvar_pointer("sv_restart");
	
	register_clcmd("chooseteam", "Command_ChooseTeam");
	
	register_event("HLTV", "Event_NewRound", "a", "1=0", "2=0");
	register_logevent("Event_RoundStart", 2, "1=Round_Start");
	
	RegisterHam(Ham_Spawn, "player", "Ham_PlayerSpawn_Pre", 0);
	RegisterHam(Ham_Spawn, "player", "Ham_PlayerSpawn_Post", 1);
	RegisterHam(Ham_Use, "func_button", "Ham_UseButton_Pre", 0);
	RegisterHam(Ham_Use, "func_door", "Ham_UseDoor_Pre", 0);
	RegisterHam(Ham_TakeDamage, "player", "Ham_TakeDamage_Pre", 0);
	
	register_forward(FM_ClientKill, "FM_ClientKill_Pre", 0);
	register_forward(FM_GetGameDescription, "FM_GetGameDescription_Pre", 0);
	
	register_touch("func_door", "weaponbox", "Engine_TouchFuncDoor");
	
	g_iHamPreThink = RegisterHam(Ham_Player_PreThink, "player", "Ham_PlayerPreThink_Post", 1);
	
	g_msgVGUIMenu = get_user_msgid("VGUIMenu");
	g_msgShowMenu = get_user_msgid("ShowMenu");
	g_msgAmmoPickup = get_user_msgid("AmmoPickup");
	g_msgWeapPickup = get_user_msgid("WeapPickup");
	
	register_message(g_msgVGUIMenu, "Message_Menu");
	register_message(g_msgShowMenu, "Message_Menu");
	
	DisableHamForward(g_iHamPreThink);
	unregister_forward(FM_Spawn, g_iForwardSpawn, 0);
	TrieDestroy(g_tRemoveEntities);
	
	set_pcvar_num(g_pSvRestart, 5);
	
	Block_Commands();
	
	g_iMaxPlayers = get_maxplayers();
}

public plugin_precache()
{
	new const szRemoveEntities[][] = 
	{
		"func_bomb_target", "func_escapezone", "func_hostage_rescue", "func_vip_safetyzone", "info_vip_start",
		"hostage_entity", "info_bomb_target", "func_buyzone","info_hostage_rescue", "monster_scientist"
	};
	g_tRemoveEntities = TrieCreate();
	for(new i = 0; i < sizeof(szRemoveEntities); i++)
	{
		TrieSetCell(g_tRemoveEntities, szRemoveEntities[i], i);
	}
	g_iForwardSpawn = register_forward(FM_Spawn, "FakeMeta_Spawn_Pre", 0);
	
	g_iEntBuyZone = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "func_buyzone"));
}

public FakeMeta_Spawn_Pre(ent)
{
	if(!pev_valid(ent)) return FMRES_IGNORED;
	
	static szClassName[32]; pev(ent, pev_classname, szClassName, charsmax(szClassName));
	
	if(TrieKeyExists(g_tRemoveEntities, szClassName))
	{
		if(ent == g_iEntBuyZone)
		{
			return FMRES_IGNORED;
		}
		engfunc(EngFunc_RemoveEntity, ent);
		return FMRES_SUPERCEDE;
	}
	return FMRES_IGNORED;
}
public plugin_natives()
{
	register_native("dr_get_terrorist", "native_get_terrorist", 1);
	register_native("dr_set_next_terrorist", "native_set_next_terrorist", 1);
}
public native_get_terrorist()
{
	return g_iTerrorist;
}
public native_set_next_terrorist(id)
{
	g_iNextTerrorist = id;
}
public client_putinserver(id)
{
	if(_get_alive_players())
	{
		block_user_spawn(id);
	}
	else
	{
		if(!is_user_connected(g_iTerrorist))
		{
			for(new i = 1; i <= g_iMaxPlayers; i++)
			{
				user_silentkill(i);
			}
		}
	}
}
public client_disconnect(id)
{
	if(id == g_iTerrorist)
	{
		new iPlayers[32], iNum;	iNum = _get_players(iPlayers, true);
		
		if(iNum >= 2)
		{
			new Float:fOrigin[3]; pev(id, pev_origin, fOrigin);
			g_iTerrorist = iPlayers[random(iNum)];
			cs_set_user_team(g_iTerrorist, CS_TEAM_T);
			ExecuteHamB(Ham_CS_RoundRespawn, g_iTerrorist);
			engfunc(EngFunc_SetOrigin, g_iTerrorist, fOrigin);
			
			new szName[32]; get_user_name(g_iTerrorist, szName, charsmax(szName));
			new szNameLeaver[32]; get_user_name(id, szNameLeaver, charsmax(szNameLeaver));
			client_print_color(0, print_team_red, "%s^3 %s^1 has left the server.^3 %s^1 became a terrorist.", PREFIX, szNameLeaver, szName);
		}
		else
		{
			set_pcvar_num(g_pSvRestart, 5);
		}
	}
}
//******** Commands ********//
public Command_ChooseTeam(id)
{
	//Add custom menu
	return PLUGIN_HANDLED;
}
//***** Block Commands *****//
Block_Commands()
{
	new szBlockedCommands[][] = {"jointeam", "joinclass", "radio1", "radio2", "radio3"};
	for(new i = 0; i < sizeof(szBlockedCommands); i++)
	{
		register_clcmd(szBlockedCommands[i], "Command_BlockCmds");
	}
}
public Command_BlockCmds(id)
{
	return PLUGIN_HANDLED;
}
//******** Events ********//
public Event_NewRound()
{
	set_pcvar_num(g_pAutoBalance, 0);
	set_pcvar_num(g_pLimitTeams, 0);
	TeamBalance();	
}
TeamBalance()
{
	new iPlayers[32], iNum, iPlayer; iNum = _get_players(iPlayers, false);
	
	if(iNum < 1 || iNum == 1 && !is_user_connected(g_iTerrorist)) return;

	if(is_user_connected(g_iTerrorist)) cs_set_user_team(g_iTerrorist, CS_TEAM_CT);
	
	if(!is_user_connected(g_iNextTerrorist))
	{
		g_iTerrorist = iPlayers[random(iNum)];
	}
	else
	{
		g_iTerrorist = g_iNextTerrorist;
		g_iNextTerrorist = 0;
	}
	
	cs_set_user_team(g_iTerrorist, CS_TEAM_T);
	for(new i = 0; i < iNum; i++)
	{
		iPlayer = iPlayers[i];
		if(iPlayer != g_iTerrorist) cs_set_user_team(iPlayer, CS_TEAM_CT);
	}
	new szName[32]; get_user_name(g_iTerrorist, szName, charsmax(szName));
	client_print_color(0, print_team_red, "%s^3 %s^1 became a terrorist.", PREFIX, szName);
}
public Event_RoundStart()
{
	TerroristCheck();
}
TerroristCheck()
{
	if(!is_user_connected(g_iTerrorist))
	{
		new players[32], pnum; get_players(players, pnum, "ace", "TERRORIST");
		g_iTerrorist = pnum ? players[0] : 0;
	}	
}
//******** Messages Credits: PRoSToTeM@ ********//
public Message_Menu(const msg, const nDest, const nClient)
{
	const MENU_TEAM = 2;
	const SHOWTEAMSELECT = 3;
	const Menu_ChooseTeam = 1;
	const m_iJoiningState = 121;
	const m_iMenu = 205;
	
	if (msg == g_msgShowMenu)
	{
		new szMsg[13];
		get_msg_arg_string(4, szMsg, charsmax(szMsg));

		if (!equal(szMsg, "#Team_Select"))
		{
			return PLUGIN_CONTINUE;
		}
	}
	else if (get_msg_arg_int(1) != MENU_TEAM || get_msg_arg_int(2) & MENU_KEY_0)
	{
		return PLUGIN_CONTINUE;
	}

	// safe checks
	if (get_pdata_int(nClient, m_iMenu) == Menu_ChooseTeam || get_pdata_int(nClient, m_iJoiningState) != SHOWTEAMSELECT)
	{
		return PLUGIN_CONTINUE;
	}

	EnableHamForward(g_iHamPreThink);

	return PLUGIN_HANDLED;
}
//*******
public Ham_PlayerSpawn_Pre(id)
{	
	g_iOldAmmoPickupBlock = get_msg_block(g_msgAmmoPickup);
	g_iOldWeapPickupBlock = get_msg_block(g_msgWeapPickup);
	set_msg_block(g_msgAmmoPickup, BLOCK_SET);
	set_msg_block(g_msgWeapPickup, BLOCK_SET);
}
public Ham_PlayerSpawn_Post(id)
{
	set_msg_block(g_msgAmmoPickup, g_iOldAmmoPickupBlock);
	set_msg_block(g_msgWeapPickup, g_iOldWeapPickupBlock);
	
	if(!is_user_alive(id)) return HAM_IGNORED;
	
	block_user_radio(id);
	
	strip_user_weapons(id);//bug with m_bHasPrimary
	give_item(id, "weapon_knife");
	
	return HAM_IGNORED;
}
public Ham_UseButton_Pre(ent, caller, activator, use_type)
{
	if(!IsPlayer(activator) || !is_user_alive(activator) || cs_get_user_team(activator) == CS_TEAM_T) return HAM_IGNORED;
		
	new Float:fMin[3], Float:fMax[3], Float:fEntOrigin[3];
	pev(ent, pev_absmin, fMin); pev(ent, pev_absmax, fMax);
	xs_vec_add(fMin, fMax, fEntOrigin);
	xs_vec_mul_scalar(fEntOrigin, 0.5, fEntOrigin);
	
	new iPlayerOrigin[3]; get_user_origin(activator, iPlayerOrigin, 1);
	new Float:fPlayerOrigin[3]; IVecFVec(iPlayerOrigin, fPlayerOrigin);
	
	new bool:bCanUse = is_in_line_of_sight(ent, fPlayerOrigin, fEntOrigin);
	
	return bCanUse ? HAM_IGNORED : HAM_SUPERCEDE;
}
public Ham_UseDoor_Pre(ent, caller, activator, use_type)
{
	return (activator && activator <= g_iMaxPlayers) ? HAM_SUPERCEDE : HAM_IGNORED;
}
public Ham_TakeDamage_Pre( id, inflictor, attacker, Float:damage, damage_bits )
{
	return (get_pcvar_num(g_pBlockFallDmg) && damage_bits & DMG_FALL && cs_get_user_team(id) == CS_TEAM_T) ? HAM_SUPERCEDE : HAM_IGNORED;
}
public Ham_PlayerPreThink_Post(id)
{
	DisableHamForward(g_iHamPreThink);

	new iOldShowMenuBlock = get_msg_block(g_msgShowMenu);
	new iOldVGUIMenuBlock = get_msg_block(g_msgVGUIMenu);
	set_msg_block(g_msgShowMenu, BLOCK_SET);
	set_msg_block(g_msgVGUIMenu, BLOCK_SET);
	engclient_cmd(id, "jointeam", "2");
	engclient_cmd(id, "joinclass", "5");
	set_msg_block(g_msgVGUIMenu, iOldVGUIMenuBlock);
	set_msg_block(g_msgShowMenu, iOldShowMenuBlock);
}
//*******
public FM_ClientKill_Pre(id)
{
	return (get_pcvar_num(g_pBlockKill) || is_user_alive(id) && cs_get_user_team(id) == CS_TEAM_T) ? FMRES_SUPERCEDE : FMRES_IGNORED;
}
public FM_GetGameDescription_Pre()
{
	static szGameName[32]; if(!szGameName[0]) formatex(szGameName, charsmax(szGameName), "Deathrun v%s", VERSION);
	forward_return(FMV_STRING, szGameName);
	return FMRES_SUPERCEDE;
}
public Engine_TouchFuncDoor(ent, toucher)
{
	if(is_valid_ent(toucher))
	{
		remove_entity(toucher);
	}
}
//****************************************//
stock _get_players(players[32], bool:alive = false)
{
	new CsTeams:team, count;
	for(new i = 1; i <= g_iMaxPlayers; i++)
	{
		if(i == g_iTerrorist) continue;
		if(!is_user_connected(i) || is_user_bot(i) || is_user_hltv(i) || alive && !is_user_alive(i)) continue;
		team = cs_get_user_team(i);
		if(team == CS_TEAM_UNASSIGNED || team == CS_TEAM_SPECTATOR) continue;
		players[count++] = i;
	}
	return count;
}
stock _get_alive_players()
{
	new players[32], pnum; get_players(players, pnum, "ach");
	return pnum;
}
stock block_user_radio(id)
{
	const m_iRadiosLeft = 192;
	set_pdata_int(id, m_iRadiosLeft, 0);
}
stock block_user_spawn(id)
{
	const m_iSpawnCount = 365;
	set_pdata_int(id, m_iSpawnCount, 1);
}
stock bool:is_in_line_of_sight(ent, Float:start[3], Float:end[3], bool:ignore_players = true)
{
	new trace = 0; engfunc(EngFunc_TraceLine, start, end, (ignore_players ? IGNORE_MONSTERS : DONT_IGNORE_MONSTERS), ent, trace);
	new Float:fraction; get_tr2(trace, TR_flFraction, fraction);
	
	if(fraction == 1.0) return true;
	
	new hit_ent = get_tr2(trace, TR_pHit);
	
	if(!pev_valid(hit_ent)) return false;
	
	new Float:fAbsMin[3]; pev(hit_ent, pev_absmin, fAbsMin);
	new Float:fAbsMax[3]; pev(hit_ent, pev_absmax, fAbsMax);
	new Float:fVolume[3]; xs_vec_sub(fAbsMax, fAbsMin, fVolume);
	
	if(fVolume[0] < 32.0 && fVolume[1] < 32.0 && fVolume[2] < 32.0) return true;
	
	return false;
}
