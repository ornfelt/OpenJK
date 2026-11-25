/*
===========================================================================
Copyright (C) 2026, OpenJK contributors

This file is part of the OpenJK source code.

OpenJK is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License version 2 as
published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, see <http://www.gnu.org/licenses/>.
===========================================================================
*/

// g_modelscale.c -- player mods: the configurable player model size (PLAYER_MODS_STATUS.md)
//
// JA++ does this with its modelscale Lua plugin; here it is built in. A client's scale comes from,
// in order: its /modelscale value (when g_modelScaleCmd allows it), modelscale.cfg for its model,
// 100. The scale goes out in ps / s.iModelScale (0 for 100, as before), which every cgame already
// draws; pmove scales the bbox and view height from it when the server says so in its serverinfo
// (g_modelScale), so the fork's cgame predicts the same box. No protocol or ABI change.

#include "g_local.h"
#include "g_modelscale.h"

#define MODELSCALE_CMD_DEFAULT	"default"	// "/modelscale default" (or 0) goes back to the table

typedef struct modelScaleClient_s {
	char		model[MAX_QPATH];	// the model the client uses ("model/skin")
	int			cmdScale;			// set by /modelscale or the server's modelscale, 0 for none
	qboolean	scaled;				// this file gave the client a scale other than 100
} modelScaleClient_t;

static modelScaleTable_t	modelScaleTable;
static modelScaleClient_t	modelScaleClients[MAX_CLIENTS];
static char					modelScaleFileBuf[MODELSCALE_CFG_MAX_SIZE];

extern gclient_t *ClientForString( const char *s );
extern qboolean StringIsInteger( const char *s );

void G_ModelScaleInit( void ) {
	fileHandle_t	f;
	int				len;

	memset( &modelScaleTable, 0, sizeof( modelScaleTable ) );
	memset( modelScaleClients, 0, sizeof( modelScaleClients ) );

	len = trap->FS_Open( MODELSCALE_CFG_FILE, &f, FS_READ );
	if ( !f ) {
		return;
	}
	if ( len <= 0 || len >= MODELSCALE_CFG_MAX_SIZE ) {
		trap->Print( S_COLOR_YELLOW "WARNING: %s: bad size %d (max %d)\n", MODELSCALE_CFG_FILE, len, MODELSCALE_CFG_MAX_SIZE - 1 );
		trap->FS_Close( f );
		return;
	}
	trap->FS_Read( modelScaleFileBuf, len, f );
	trap->FS_Close( f );
	modelScaleFileBuf[len] = '\0';

	Q_ModelScaleParse( &modelScaleTable, modelScaleFileBuf, MODELSCALE_CFG_FILE, Com_Printf );
	trap->Print( "%s: %d model sizes\n", MODELSCALE_CFG_FILE, modelScaleTable.numEntries );
}

void G_ModelScaleClientReset( int clientNum ) {
	if ( clientNum < 0 || clientNum >= MAX_CLIENTS ) {
		return;
	}
	memset( &modelScaleClients[clientNum], 0, sizeof( modelScaleClients[clientNum] ) );
}

static void G_ModelScaleRange( int *min, int *max ) {
	Q_ModelScaleParseRange( g_modelScaleRange.string, min, max );
}

// the scale the precedence gives the client and where it came from
static int G_ModelScaleWanted( int clientNum, const char **source ) {
	const modelScaleClient_t	*mc = &modelScaleClients[clientNum];
	int							scale, min, max;

	if ( g_modelScaleCmd.integer && mc->cmdScale ) {
		G_ModelScaleRange( &min, &max );
		*source = "/modelscale";
		return Q_ModelScaleClamp( mc->cmdScale, min, max );
	}
	scale = Q_ModelScaleLookup( &modelScaleTable, mc->model, NULL );
	if ( scale ) {
		*source = MODELSCALE_CFG_FILE;
		return scale;
	}
	*source = "default";
	return MODELSCALE_DEFAULT;
}

// the bbox and view height pmove gives a client of this scale in its current state
static void G_ModelScaleBBox( const gclient_t *client, float factor, vec3_t mins, vec3_t maxs, int *viewHeight ) {
	const playerState_t	*ps = &client->ps;
	const float			halfWidth = BG_ModelScaleHalfWidth( factor );

	VectorSet( mins, -halfWidth, -halfWidth, MINS_Z );
	VectorSet( maxs, halfWidth, halfWidth, 0 );
	if ( ps->pm_type == PM_DEAD ) {
		maxs[2] = BG_ModelScaleZ( -8, factor );
		*viewHeight = BG_ModelScaleViewHeight( DEAD_VIEWHEIGHT, factor );
	} else if ( ps->pm_flags & PMF_DUCKED ) {
		maxs[2] = BG_ModelScaleZ( ps->crouchheight, factor );
		*viewHeight = BG_ModelScaleViewHeight( CROUCH_VIEWHEIGHT, factor );
	} else if ( ps->pm_flags & PMF_ROLLING ) {
		maxs[2] = BG_ModelScaleZ( ps->crouchheight, factor );
		*viewHeight = BG_ModelScaleViewHeight( DEFAULT_VIEWHEIGHT, factor );
	} else {
		maxs[2] = BG_ModelScaleZ( ps->standheight, factor );
		*viewHeight = BG_ModelScaleViewHeight( DEFAULT_VIEWHEIGHT, factor );
	}
}

static qboolean G_ModelScaleFits( const gentity_t *ent, const vec3_t mins, const vec3_t maxs ) {
	trace_t	tr;

	trap->Trace( &tr, ent->client->ps.origin, mins, maxs, ent->client->ps.origin, ent->s.number, ent->clipmask, qfalse, 0, 0 );
	return (qboolean)(!tr.startsolid && !tr.allsolid);
}

qboolean G_ModelScaleApply( gentity_t *ent, qboolean checkFit ) {
	gclient_t			*client = ent->client;
	modelScaleClient_t	*mc;
	const char			*source;
	int					scale, oldScale, viewHeight;
	float				factor;
	vec3_t				mins, maxs;

	if ( !client || ent->s.number >= MAX_CLIENTS ) {
		return qtrue;
	}
	mc = &modelScaleClients[ent->s.number];

	if ( g_modelScale.integer ) {
		scale = G_ModelScaleWanted( ent->s.number, &source );
	} else if ( mc->scaled ) {
		scale = MODELSCALE_DEFAULT; // switched off: undo what this file did
	} else {
		return qtrue; // switched off: the game as before
	}

	oldScale = client->ps.iModelScale ? client->ps.iModelScale : MODELSCALE_DEFAULT;
	factor = scale / MODELSCALE_PERCENT;
	G_ModelScaleBBox( client, factor, mins, maxs, &viewHeight );

	if ( checkFit && scale > oldScale && client->sess.sessionTeam != TEAM_SPECTATOR && !G_ModelScaleFits( ent, mins, maxs ) ) {
		trap->SendServerCommand( ent->s.number, va( "print \"modelscale: no room for %d%% here, it applies when you respawn\n\"", scale ) );
		return qfalse;
	}

	client->ps.iModelScale = ent->s.iModelScale = (scale == MODELSCALE_DEFAULT) ? 0 : scale;
	if ( client->ps.iModelScale ) {
		VectorSet( ent->modelScale, factor, factor, factor );
	} else {
		VectorClear( ent->modelScale );
	}
	mc->scaled = (qboolean)(scale != MODELSCALE_DEFAULT);

	if ( client->ps.pm_flags & PMF_FIX_MINS ) {
		mins[2] = ent->r.mins[2]; // a jump attack's raised mins: pmove drops them itself
	}
	VectorCopy( mins, ent->r.mins );
	VectorCopy( maxs, ent->r.maxs );
	client->ps.viewheight = viewHeight;
	if ( ent->r.linked ) {
		trap->LinkEntity( (sharedEntity_t *)ent );
	}
	return qtrue;
}

void G_ModelScaleUserinfoChanged( gentity_t *ent, const char *model ) {
	modelScaleClient_t *mc;

	if ( !ent->client || ent->s.number >= MAX_CLIENTS ) {
		return;
	}
	mc = &modelScaleClients[ent->s.number];
	if ( !Q_stricmp( mc->model, model ) ) {
		return;
	}
	Q_strncpyz( mc->model, model, sizeof( mc->model ) );
	if ( ent->client->pers.connected == CON_CONNECTED ) {
		G_ModelScaleApply( ent, qtrue );
	}
}

void G_ModelScaleNPC( gentity_t *npc, const char *model, const char *skin ) {
	gclient_t	*client = npc->client;
	int			scale, npcScale;
	float		factor, halfWidth;

	if ( !g_modelScale.integer || !client ) {
		return;
	}

	npcScale = client->ps.iModelScale ? client->ps.iModelScale : MODELSCALE_DEFAULT;
	scale = Q_ModelScaleLookup( &modelScaleTable, model, skin );
	if ( !scale ) {
		scale = npcScale;
	}
	if ( scale == MODELSCALE_DEFAULT ) {
		client->ps.iModelScale = npc->s.iModelScale = 0;
		VectorClear( npc->modelScale );
		return;
	}

	factor = scale / MODELSCALE_PERCENT;
	client->ps.iModelScale = npc->s.iModelScale = scale;
	VectorSet( npc->modelScale, factor, factor, factor );

	// a bbox the .npc file sized itself (width / height / crouchheight) is left as it is
	if ( npc->r.maxs[0] != MODELSCALE_HALF_WIDTH || npc->r.mins[2] != DEFAULT_MINS_2 || npc->r.maxs[2] != DEFAULT_MAXS_2
		|| client->ps.standheight != DEFAULT_MAXS_2 || client->ps.crouchheight != CROUCH_MAXS_2 ) {
		return;
	}
	halfWidth = BG_ModelScaleHalfWidth( factor );
	VectorSet( npc->r.mins, -halfWidth, -halfWidth, DEFAULT_MINS_2 );
	VectorSet( npc->r.maxs, halfWidth, halfWidth, BG_ModelScaleZ( DEFAULT_MAXS_2, factor ) );
	client->ps.standheight = BG_ModelScaleViewHeight( DEFAULT_MAXS_2, factor );
	client->ps.crouchheight = BG_ModelScaleViewHeight( CROUCH_MAXS_2, factor );
}

float G_ModelScaleDrawOffset( const gentity_t *ent ) {
	if ( !g_modelScale.integer || !ent->client || !ent->modelScale[2] || ent->s.NPC_class == CLASS_VEHICLE ) {
		return 0.0f;
	}
	return BG_ModelScaleDrawOffset( ent->modelScale[2] );
}

void G_ModelScaleCvarChanged( void ) {
	int i;

	if ( !level.clients ) {
		return; // registering the cvars: no clients yet
	}
	for ( i = 0; i < level.maxclients && i < MAX_CLIENTS; i++ ) {
		gentity_t *ent = &g_entities[i];

		if ( ent->inuse && ent->client && ent->client->pers.connected == CON_CONNECTED ) {
			G_ModelScaleApply( ent, qtrue );
		}
	}
}

// "n" or "default" / "0" into a scale (0 = back to the table); qfalse when it is neither
static qboolean G_ModelScaleParseArg( const char *arg, int *scale ) {
	if ( !Q_stricmp( arg, MODELSCALE_CMD_DEFAULT ) ) {
		*scale = 0;
		return qtrue;
	}
	if ( !StringIsInteger( arg ) ) {
		return qfalse;
	}
	*scale = atoi( arg );
	return (qboolean)(*scale >= 0);
}

static int G_ModelScaleCurrent( const gclient_t *client ) {
	return client->ps.iModelScale ? client->ps.iModelScale : MODELSCALE_DEFAULT;
}

// stores the command's scale for the client (0 = none) and applies it; the scale is clamped.
// qfalse when the size waits for the next spawn
static qboolean G_ModelScaleSetCmd( gentity_t *ent, int scale ) {
	int min, max;

	G_ModelScaleRange( &min, &max );
	modelScaleClients[ent->s.number].cmdScale = scale ? Q_ModelScaleClamp( scale, min, max ) : 0;
	return G_ModelScaleApply( ent, qtrue );
}

void Cmd_ModelScale_f( gentity_t *ent ) {
	char		arg[MAX_TOKEN_CHARS];
	const char	*source;
	int			scale, min, max;

	if ( trap->Argc() < 2 ) {
		if ( !g_modelScale.integer ) {
			trap->SendServerCommand( ent->s.number, "print \"modelscale: model scaling is off on this server\n\"" );
			return;
		}
		G_ModelScaleWanted( ent->s.number, &source );
		G_ModelScaleRange( &min, &max );
		trap->SendServerCommand( ent->s.number, va( "print \"your model scale is %d (%s), /modelscale <%d-%d | %s>\n\"",
			G_ModelScaleCurrent( ent->client ), source, min, max, MODELSCALE_CMD_DEFAULT ) );
		return;
	}

	if ( !g_modelScale.integer ) {
		trap->SendServerCommand( ent->s.number, "print \"modelscale: model scaling is off on this server\n\"" );
		return;
	}
	if ( !g_modelScaleCmd.integer ) {
		trap->SendServerCommand( ent->s.number, "print \"modelscale: the /modelscale command is off on this server\n\"" );
		return;
	}

	trap->Argv( 1, arg, sizeof( arg ) );
	if ( !G_ModelScaleParseArg( arg, &scale ) ) {
		G_ModelScaleRange( &min, &max );
		trap->SendServerCommand( ent->s.number, va( "print \"usage: /modelscale [%d-%d | %s]\n\"", min, max, MODELSCALE_CMD_DEFAULT ) );
		return;
	}

	if ( !G_ModelScaleSetCmd( ent, scale ) ) {
		return; // it said why
	}
	scale = G_ModelScaleWanted( ent->s.number, &source );
	trap->SendServerCommand( ent->s.number, va( "print \"setting model scale to %d (%s)\n\"", scale, source ) );
}

// "modelscale <client> <n | default>" on the server console / rcon
static void Svcmd_ModelScale_f( void ) {
	char		who[MAX_TOKEN_CHARS], arg[MAX_TOKEN_CHARS];
	gclient_t	*cl;
	int			scale;
	const char	*source;

	trap->Argv( 1, who, sizeof( who ) );
	trap->Argv( 2, arg, sizeof( arg ) );
	if ( !G_ModelScaleParseArg( arg, &scale ) ) {
		trap->Print( "usage: modelscale <client> <percent | %s>\n", MODELSCALE_CMD_DEFAULT );
		return;
	}
	cl = ClientForString( who );
	if ( !cl ) {
		return;
	}
	G_ModelScaleSetCmd( &g_entities[cl - level.clients], scale );
	scale = G_ModelScaleWanted( cl - level.clients, &source );
	trap->Print( "%s" S_COLOR_WHITE ": model scale %d (%s), now %d\n", cl->pers.netname, scale, source, G_ModelScaleCurrent( cl ) );
}

// "modelscales": the table, then every client's scale
static void Svcmd_ModelScales_f( void ) {
	const char	*source;
	int			i;

	trap->Print( "%s (%d):\n", MODELSCALE_CFG_FILE, modelScaleTable.numEntries );
	for ( i = 0; i < modelScaleTable.numEntries; i++ ) {
		trap->Print( "  %-24s %d\n", modelScaleTable.entries[i].model, modelScaleTable.entries[i].scale );
	}
	trap->Print( "clients (g_modelScale %d, g_modelScaleCmd %d, g_modelScaleRange \"%s\"):\n",
		g_modelScale.integer, g_modelScaleCmd.integer, g_modelScaleRange.string );
	for ( i = 0; i < level.maxclients && i < MAX_CLIENTS; i++ ) {
		const gclient_t *cl = &level.clients[i];

		if ( cl->pers.connected != CON_CONNECTED ) {
			continue;
		}
		G_ModelScaleWanted( i, &source );
		if ( !g_modelScale.integer ) {
			source = "off";
		}
		trap->Print( "  %2d %-24s %3d (%s) bbox %.1f..%.1f x %.1f..%.1f view %d %s\n", i, modelScaleClients[i].model,
			G_ModelScaleCurrent( cl ), source, g_entities[i].r.mins[0], g_entities[i].r.maxs[0], g_entities[i].r.mins[2],
			g_entities[i].r.maxs[2], cl->ps.viewheight, cl->pers.netname );
	}
}

qboolean G_ModelScaleConsoleCommand( void ) {
	char cmd[MAX_TOKEN_CHARS];

	trap->Argv( 0, cmd, sizeof( cmd ) );
	if ( !Q_stricmp( cmd, "modelscales" ) ) {
		Svcmd_ModelScales_f();
		return qtrue;
	}
	if ( !Q_stricmp( cmd, "modelscale" ) ) {
		if ( trap->Argc() == 3 ) {
			Svcmd_ModelScale_f();
			return qtrue;
		}
		if ( dedicated.integer ) {
			trap->Print( "usage: modelscale <client> <percent | %s>\n", MODELSCALE_CMD_DEFAULT );
			return qtrue;
		}
		return qfalse; // a listen server's own player: on to the client command
	}
	return qfalse;
}
