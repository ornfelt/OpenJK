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

// bg_modelscale.h -- player mods: the player model size, shared by game and cgame
// (PLAYER_MODS_STATUS.md)

#pragma once

#include "qcommon/q_shared.h"

// scales are whole percents, as in entityState_t / playerState_t iModelScale (0 there means 100)
#define MODELSCALE_DEFAULT			100
#define MODELSCALE_HARD_MIN			10		// below this the bbox is thinner than a step trace
#define MODELSCALE_HARD_MAX			250		// the stand view height still fits ps.viewheight's 8 bits
#define MODELSCALE_RANGE_DEFAULT	"30 200"	// "<min> <max>" for /modelscale: Grogu to past Grievous
#define MODELSCALE_PERCENT			100.0f	// modelscale.cfg holds factors (0.5), the game percents

#define MODELSCALE_CFG_FILE			"modelscale.cfg"
#define MODELSCALE_CFG_MAX_SIZE		65536
#define MODELSCALE_MAX_ENTRIES		512

// the serverinfo key telling clients that pmove scales the player bbox and view height
#define MODELSCALE_SERVERINFO_KEY	"g_modelScale"

#define MODELSCALE_HALF_WIDTH		15		// a player's bbox half width at scale 100 (bg_pmove.c)

typedef struct modelScaleEntry_s {
	char	model[MAX_QPATH];	// "model" or "model/skin", as written in the file
	int		scale;				// percent
} modelScaleEntry_t;

typedef struct modelScaleTable_s {
	modelScaleEntry_t	entries[MODELSCALE_MAX_ENTRIES];
	int					numEntries;
} modelScaleTable_t;

// the modelscale.cfg format (JA++'s): whitespace-separated "model scale" pairs, scale a factor,
// "//" and "/* */" comments; a later entry for the same model replaces the earlier one
int BG_ModelScaleParse( modelScaleTable_t *table, const char *text, const char *fileName );

// the table's scale for "model" or "model/skin" (the skin entry first), 0 when it has none
int BG_ModelScaleLookup( const modelScaleTable_t *table, const char *model, const char *skin );

// "<min> <max>" in percent, both kept inside the hard limits; a broken string gives the default
void BG_ModelScaleParseRange( const char *str, int *outMin, int *outMax );

int BG_ModelScaleClamp( int scale, int min, int max );

// the size factor pmove applies to a player: 1 unless enabled and a client with a scale
float BG_ModelScaleFactor( const playerState_t *ps, qboolean enabled );

// a height above the origin (maxs[2], a view height) scaled with the feet kept at MINS_Z, the way
// the cgame draws a scaled player (CG_Player raises the model by 24 * (scale - 1))
float BG_ModelScaleZ( float z, float factor );
int BG_ModelScaleViewHeight( int viewHeight, float factor );
float BG_ModelScaleHalfWidth( float factor );

// how far CG_Player raises a scaled (non-vehicle) model above its origin: 24 * (factor - 1)
float BG_ModelScaleDrawOffset( float factor );
