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

// g_modelscale.cpp -- player mods: the configurable player model size in SP (PLAYER_MODS_STATUS.md)
//
// The same modelscale.cfg and cvars as MP (shared/qcommon/q_modelscale.c parses the file). The
// player's scale comes from, in order: its modelscale command (when g_modelScaleCmd allows it),
// modelscale.cfg for its model, the .npc file's scale (playermodel <npc>), 100; an npc keeps its
// .npc file's scale, the cfg sizes the npcs that have none (the user's choice, 2026-11-25). SP pmove already sizes the bbox and view height from the entity's
// mins / maxs and the client's stand / crouch heights, and the cgame draws s.modelScale with the
// feet kept at DEFAULT_MINS_2, so setting those is all it takes. All of them are in the savegame
// already; the command's value is kept in a CVAR_SAVEGAME cvar. No savegame format change.
//
// The bbox: each of width, stand height and crouch height follows the scale on its own. A value
// the .npc file set belongs to the .npc scale, a default one to 100, and each is rescaled from
// there (heights above the feet), so at the .npc scale the file's own values come out unchanged.

#include "g_local.h"
#include "g_modelscale.h"

#define MODELSCALE_CMD_DEFAULT	"default"	// "modelscale default" (or 0) goes back to the table
#define MODELSCALE_MODEL_PREFIX	"models/players/"

static cvar_t	*g_modelScale;
static cvar_t	*g_modelScaleCmd;
static cvar_t	*g_modelScaleRange;
static cvar_t	*g_modelScaleSaved;		// the player's command scale, 0 for none (in the savegame)

static modelScaleTable_t	modelScaleTable;
static char					modelScaleFileBuf[MODELSCALE_CFG_MAX_SIZE];
static int					modelScaleCvarCounts[3];

// a model's bbox as it came (from NPC_ParseParms or the defaults) and the scale each part belongs to
typedef struct modelScaleBBox_s {
	float	halfWidth;
	int		standHeight;
	int		crouchHeight;
	int		widthScale, standScale, crouchScale;
	int		npcScale;
} modelScaleBBox_t;

// what the player's scale is made of; set again by every model change (the module reloads per map)
typedef struct playerModelScale_s {
	qboolean			known;
	char				model[MODELSCALE_MODEL_SIZE];
	char				skin[MODELSCALE_MODEL_SIZE];
	modelScaleBBox_t	base;
	qboolean			scaled;		// this file changed the player's size or bbox
} playerModelScale_t;

static playerModelScale_t	playerScale;

static void G_ModelScalePrint( const char *fmt, ... ) {
	va_list	argptr;
	char	text[MAX_STRING_CHARS];

	va_start( argptr, fmt );
	Q_vsnprintf( text, sizeof( text ), fmt, argptr );
	va_end( argptr );
	gi.Printf( "%s", text );
}

static int G_ModelScaleCvarCount( int i ) {
	const cvar_t *cvars[] = { g_modelScale, g_modelScaleCmd, g_modelScaleRange };
	return cvars[i]->modificationCount;
}

void G_ModelScaleInit( void ) {
	fileHandle_t	f;
	int				len, i;

	g_modelScale = gi.cvar( "g_modelScale", "1", CVAR_ARCHIVE );
	g_modelScaleCmd = gi.cvar( "g_modelScaleCmd", "1", CVAR_ARCHIVE );
	g_modelScaleRange = gi.cvar( "g_modelScaleRange", MODELSCALE_RANGE_DEFAULT, CVAR_ARCHIVE );
	g_modelScaleSaved = gi.cvar( "g_modelScaleSaved", "0", CVAR_SAVEGAME );
	for ( i = 0; i < (int)ARRAY_LEN( modelScaleCvarCounts ); i++ ) {
		modelScaleCvarCounts[i] = G_ModelScaleCvarCount( i );
	}

	memset( &modelScaleTable, 0, sizeof( modelScaleTable ) );
	memset( &playerScale, 0, sizeof( playerScale ) );

	len = gi.FS_FOpenFile( MODELSCALE_CFG_FILE, &f, FS_READ );
	if ( !f ) {
		return;
	}
	if ( len <= 0 || len >= MODELSCALE_CFG_MAX_SIZE ) {
		gi.Printf( S_COLOR_YELLOW "WARNING: %s: bad size %d (max %d)\n", MODELSCALE_CFG_FILE, len, MODELSCALE_CFG_MAX_SIZE - 1 );
		gi.FS_FCloseFile( f );
		return;
	}
	gi.FS_Read( modelScaleFileBuf, len, f );
	gi.FS_FCloseFile( f );
	modelScaleFileBuf[len] = '\0';

	Q_ModelScaleParse( &modelScaleTable, modelScaleFileBuf, MODELSCALE_CFG_FILE, G_ModelScalePrint );
	gi.Printf( "%s: %d model sizes\n", MODELSCALE_CFG_FILE, modelScaleTable.numEntries );
}

int G_ModelScalePercent( float factor ) {
	return factor > 0.0f ? (int)floorf( factor * MODELSCALE_PERCENT + 0.5f ) : MODELSCALE_DEFAULT;
}

// a height above the origin, belonging to fromScale, for toScale with the feet kept at
// DEFAULT_MINS_2 (where the cgame draws them)
static int G_ModelScaleHeight( int height, int fromScale, int toScale ) {
	return (int)floorf( DEFAULT_MINS_2 + (height - DEFAULT_MINS_2) * (float)toScale / fromScale + 0.5f );
}

// "models/players/<model>/model.glm" of the entity's ghoul2 model into model; qfalse without one
static qboolean G_ModelScaleGhoul2Model( const gentity_t *ent, char *model, int size ) {
	const char	*name, *slash;
	int			len;

	if ( ent->playerModel < 0 || ent->playerModel >= ent->ghoul2.size() ) {
		return qfalse;
	}
	name = ent->ghoul2[ent->playerModel].mFileName;
	if ( Q_stricmpn( name, MODELSCALE_MODEL_PREFIX, (int)strlen( MODELSCALE_MODEL_PREFIX ) ) ) {
		return qfalse;
	}
	name += strlen( MODELSCALE_MODEL_PREFIX );
	slash = strchr( name, '/' );
	len = slash ? (int)(slash - name) : (int)strlen( name );
	if ( len <= 0 || len >= size ) {
		return qfalse;
	}
	Q_strncpyz( model, name, len + 1 );
	return qtrue;
}

// the entity's bbox as it is now, each part tagged with the scale it belongs to
static void G_ModelScaleBBoxBase( const gentity_t *ent, int npcScale, modelScaleBBox_t *base ) {
	base->halfWidth = ent->maxs[0];
	base->standHeight = ent->client->standheight;
	base->crouchHeight = ent->client->crouchheight;
	base->widthScale = (ent->mins[0] == DEFAULT_MINS_0 && ent->maxs[0] == DEFAULT_MAXS_0) ? MODELSCALE_DEFAULT : npcScale;
	base->standScale = (base->standHeight == DEFAULT_MAXS_2) ? MODELSCALE_DEFAULT : npcScale;
	base->crouchScale = (base->crouchHeight == CROUCH_MAXS_2) ? MODELSCALE_DEFAULT : npcScale;
	base->npcScale = npcScale;
}

static void G_ModelScaleRange( int *min, int *max ) {
	Q_ModelScaleParseRange( g_modelScaleRange->string, min, max );
}

// the player's scale by the precedence, and where it came from
static int G_ModelScalePlayerWanted( const char **source ) {
	int scale, min, max;

	if ( g_modelScaleCmd->integer && g_modelScaleSaved->integer > 0 ) {
		G_ModelScaleRange( &min, &max );
		*source = "modelscale";
		return Q_ModelScaleClamp( g_modelScaleSaved->integer, min, max );
	}
	scale = Q_ModelScaleLookup( &modelScaleTable, playerScale.model, playerScale.skin );
	if ( scale ) {
		*source = MODELSCALE_CFG_FILE;
		return scale;
	}
	if ( playerScale.base.npcScale != MODELSCALE_DEFAULT ) {
		*source = ".npc";
		return playerScale.base.npcScale;
	}
	*source = "default";
	return MODELSCALE_DEFAULT;
}

// the bbox of base at the given scale, standing or crouched as the client is now
static void G_ModelScaleBBox( const gentity_t *ent, const modelScaleBBox_t *base, int scale, vec3_t mins, vec3_t maxs,
	int *standHeight, int *crouchHeight ) {
	const float halfWidth = base->halfWidth * scale / base->widthScale;

	*standHeight = G_ModelScaleHeight( base->standHeight, base->standScale, scale );
	*crouchHeight = G_ModelScaleHeight( base->crouchHeight, base->crouchScale, scale );
	VectorSet( mins, -halfWidth, -halfWidth, DEFAULT_MINS_2 );
	VectorSet( maxs, halfWidth, halfWidth, (ent->client->ps.pm_flags & PMF_DUCKED) ? *crouchHeight : *standHeight );
}

static void G_ModelScaleSetBBox( gentity_t *ent, const vec3_t mins, const vec3_t maxs, int standHeight, int crouchHeight ) {
	VectorCopy( mins, ent->mins );
	VectorCopy( maxs, ent->maxs );
	ent->client->standheight = standHeight;
	ent->client->crouchheight = crouchHeight;
	if ( ent->linked ) {
		gi.linkentity( ent );
	}
}

// sets the entity's scale and its bbox for it; with checkFit a bigger bbox that would start in
// solid is refused. qfalse when refused.
static qboolean G_ModelScaleSet( gentity_t *ent, int scale, const modelScaleBBox_t *base, qboolean checkFit ) {
	const float	factor = scale / MODELSCALE_PERCENT;
	const int	oldScale = G_ModelScalePercent( ent->s.modelScale[2] );
	vec3_t		mins, maxs;
	int			standHeight, crouchHeight;
	trace_t		tr;

	G_ModelScaleBBox( ent, base, scale, mins, maxs, &standHeight, &crouchHeight );
	if ( checkFit && scale > oldScale ) {
		gi.trace( &tr, ent->currentOrigin, mins, maxs, ent->currentOrigin, ent->s.number, ent->clipmask, G2_NOCOLLIDE, 0 );
		if ( tr.startsolid || tr.allsolid ) {
			gi.Printf( "modelscale: no room for %d%% here\n", scale );
			return qfalse;
		}
	}
	VectorSet( ent->s.modelScale, factor, factor, factor );
	G_ModelScaleSetBBox( ent, mins, maxs, standHeight, crouchHeight );
	return qtrue;
}

// back to what the game alone would have: the .npc scale and the bbox as it came
static void G_ModelScaleRestore( gentity_t *ent, const modelScaleBBox_t *base ) {
	const float	factor = base->npcScale / MODELSCALE_PERCENT;
	vec3_t		mins, maxs;

	VectorSet( mins, -base->halfWidth, -base->halfWidth, DEFAULT_MINS_2 );
	VectorSet( maxs, base->halfWidth, base->halfWidth,
		(ent->client->ps.pm_flags & PMF_DUCKED) ? base->crouchHeight : base->standHeight );
	VectorSet( ent->s.modelScale, factor, factor, factor );
	G_ModelScaleSetBBox( ent, mins, maxs, base->standHeight, base->crouchHeight );
}

// the player's scale from the precedence; qfalse when a bigger size did not fit
static qboolean G_ModelScaleApplyPlayer( gentity_t *ent, qboolean checkFit ) {
	const char	*source;
	int			scale;

	if ( !playerScale.known ) {
		return qtrue;
	}
	if ( !g_modelScale->integer ) {
		if ( playerScale.scaled ) { // switched off: back to what the game would have
			G_ModelScaleRestore( ent, &playerScale.base );
			playerScale.scaled = qfalse;
		}
		return qtrue;
	}
	scale = G_ModelScalePlayerWanted( &source );
	if ( !G_ModelScaleSet( ent, scale, &playerScale.base, checkFit ) ) {
		return qfalse;
	}
	playerScale.scaled = qtrue;
	return qtrue;
}

void G_ModelScaleSetModel( gentity_t *ent, const char *model, const char *skin, int npcScale, qboolean bboxFromNpc ) {
	char				ghoulModel[MODELSCALE_MODEL_SIZE];
	modelScaleBBox_t	base;
	int					scale;

	if ( !ent || !ent->client || ent->client->NPC_class == CLASS_VEHICLE || !g_modelScale ) {
		return;
	}
	if ( !model ) {
		if ( !G_ModelScaleGhoul2Model( ent, ghoulModel, sizeof( ghoulModel ) ) ) {
			return;
		}
		model = ghoulModel;
	}

	if ( ent->s.number ) { // an npc: its own .npc scale wins, the cfg sizes the npcs that have none
		if ( !g_modelScale->integer ) {
			return;
		}
		scale = npcScale;
		if ( npcScale == MODELSCALE_DEFAULT ) {
			scale = Q_ModelScaleLookup( &modelScaleTable, model, skin );
			if ( !scale ) {
				scale = MODELSCALE_DEFAULT;
			}
		}
		if ( scale != MODELSCALE_DEFAULT || npcScale != MODELSCALE_DEFAULT ) {
			G_ModelScaleBBoxBase( ent, npcScale, &base );
			G_ModelScaleSet( ent, scale, &base, qfalse );
		}
		return;
	}

	if ( !bboxFromNpc && g_modelScale->integer ) {
		// a plain model (character creation, a savegame): the default bbox, scaled below
		VectorSet( ent->mins, DEFAULT_MINS_0, DEFAULT_MINS_1, DEFAULT_MINS_2 );
		VectorSet( ent->maxs, DEFAULT_MAXS_0, DEFAULT_MAXS_1, DEFAULT_MAXS_2 );
		ent->client->standheight = DEFAULT_MAXS_2;
		ent->client->crouchheight = CROUCH_MAXS_2;
	}
	G_ModelScaleBBoxBase( ent, npcScale, &playerScale.base );

	playerScale.known = qtrue;
	Q_strncpyz( playerScale.model, model, sizeof( playerScale.model ) );
	Q_strncpyz( playerScale.skin, (skin && !strchr( skin, '|' )) ? skin : "", sizeof( playerScale.skin ) );
	G_ModelScaleApplyPlayer( ent, qfalse );
}

void G_ModelScaleRunFrame( void ) {
	qboolean	changed = qfalse;
	int			i;

	if ( !g_modelScale ) {
		return;
	}
	for ( i = 0; i < (int)ARRAY_LEN( modelScaleCvarCounts ); i++ ) {
		if ( modelScaleCvarCounts[i] != G_ModelScaleCvarCount( i ) ) {
			modelScaleCvarCounts[i] = G_ModelScaleCvarCount( i );
			changed = qtrue;
		}
	}
	if ( changed && g_entities[0].inuse && g_entities[0].client ) {
		G_ModelScaleApplyPlayer( &g_entities[0], qtrue );
	}
}

void Svcmd_ModelScale_f( void ) {
	gentity_t	*player = &g_entities[0];
	const char	*arg, *source;
	int			scale, min, max, old;

	if ( !player->inuse || !player->client ) {
		return;
	}
	G_ModelScaleRange( &min, &max );
	if ( !g_modelScale->integer ) {
		gi.Printf( "modelscale: model scaling is off (g_modelScale 0)\n" );
		return;
	}
	if ( gi.argc() < 2 ) {
		G_ModelScalePlayerWanted( &source );
		gi.Printf( "your model scale is %d (%s), modelscale <%d-%d | %s>\n", G_ModelScalePercent( player->s.modelScale[2] ),
			source, min, max, MODELSCALE_CMD_DEFAULT );
		return;
	}
	if ( !g_modelScaleCmd->integer ) {
		gi.Printf( "modelscale: the modelscale command is off (g_modelScaleCmd 0)\n" );
		return;
	}

	arg = gi.argv( 1 );
	if ( !Q_stricmp( arg, MODELSCALE_CMD_DEFAULT ) ) {
		scale = 0;
	} else if ( arg[0] >= '0' && arg[0] <= '9' ) {
		scale = atoi( arg );
		scale = scale ? Q_ModelScaleClamp( scale, min, max ) : 0;
	} else {
		gi.Printf( "usage: modelscale [%d-%d | %s]\n", min, max, MODELSCALE_CMD_DEFAULT );
		return;
	}

	old = g_modelScaleSaved->integer;
	gi.cvar_set( "g_modelScaleSaved", va( "%d", scale ) );
	if ( !G_ModelScaleApplyPlayer( player, qtrue ) ) {
		gi.cvar_set( "g_modelScaleSaved", va( "%d", old ) ); // no room: keep the old size
		return;
	}
	scale = G_ModelScalePlayerWanted( &source );
	gi.Printf( "setting model scale to %d (%s)\n", scale, source );
}

void Svcmd_ModelScales_f( void ) {
	const gentity_t	*player = &g_entities[0];
	const char		*source;
	int				i;

	gi.Printf( "%s (%d):\n", MODELSCALE_CFG_FILE, modelScaleTable.numEntries );
	for ( i = 0; i < modelScaleTable.numEntries; i++ ) {
		gi.Printf( "  %-24s %d\n", modelScaleTable.entries[i].model, modelScaleTable.entries[i].scale );
	}
	gi.Printf( "player (g_modelScale %d, g_modelScaleCmd %d, g_modelScaleRange \"%s\", g_modelScaleSaved %d):\n",
		g_modelScale->integer, g_modelScaleCmd->integer, g_modelScaleRange->string, g_modelScaleSaved->integer );
	if ( player->inuse && player->client ) {
		G_ModelScalePlayerWanted( &source );
		gi.Printf( "  %-24s %3d (%s) bbox %.1f..%.1f x %.1f..%.1f stand %d crouch %d view %d\n", playerScale.model,
			G_ModelScalePercent( player->s.modelScale[2] ), g_modelScale->integer ? source : "off", player->mins[0],
			player->maxs[0], player->mins[2], player->maxs[2], player->client->standheight, player->client->crouchheight,
			player->client->ps.viewheight );
	}
	for ( i = 1; i < globals.num_entities; i++ ) {
		const gentity_t *npc = &g_entities[i];

		if ( !npc->inuse || !npc->client || !npc->NPC ) {
			continue;
		}
		gi.Printf( "  npc %4d %-20s %3d bbox %.1f..%.1f x %.1f..%.1f stand %d crouch %d\n", i, npc->NPC_type ? npc->NPC_type : "?",
			G_ModelScalePercent( npc->s.modelScale[2] ), npc->mins[0], npc->maxs[0], npc->mins[2], npc->maxs[2],
			npc->client->standheight, npc->client->crouchheight );
	}
}
