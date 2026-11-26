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

// q_modelscale.h -- player mods: the modelscale.cfg table, shared by the SP and MP game modules
// and the MP cgame (PLAYER_MODS_STATUS.md)

#pragma once

#if defined(__cplusplus)
extern "C" {
#endif

// scales are whole percents, as in MP's iModelScale (0 there means 100)
#define MODELSCALE_DEFAULT			100
#define MODELSCALE_HARD_MIN			10		// below this the bbox is thinner than a step trace
#define MODELSCALE_HARD_MAX			250		// MP: the stand view height still fits ps.viewheight's 8 bits
#define MODELSCALE_RANGE_DEFAULT	"20 200"	// "<min> <max>" for /modelscale: Grogu (22) to past Grievous
#define MODELSCALE_PERCENT			100.0f	// modelscale.cfg holds factors (0.5), the games percents

#define MODELSCALE_CFG_FILE			"modelscale.cfg"
#define MODELSCALE_CFG_MAX_SIZE		65536
#define MODELSCALE_MAX_ENTRIES		512
#define MODELSCALE_MODEL_SIZE		64		// MAX_QPATH in both games

typedef void (*modelScalePrint_t)( const char *fmt, ... );

typedef struct modelScaleEntry_s {
	char	model[MODELSCALE_MODEL_SIZE];	// "model" or "model/skin", as written in the file
	int		scale;							// percent
} modelScaleEntry_t;

typedef struct modelScaleTable_s {
	modelScaleEntry_t	entries[MODELSCALE_MAX_ENTRIES];
	int					numEntries;
} modelScaleTable_t;

// the modelscale.cfg format (JA++'s): whitespace-separated "model scale" pairs, scale a factor,
// "//" and "/* */" comments; a later entry for the same model replaces the earlier one. Adds the
// pairs of text to table and returns how many it read; warnings go to print.
int Q_ModelScaleParse( modelScaleTable_t *table, const char *text, const char *fileName, modelScalePrint_t print );

// the table's scale for "model" or "model/skin" (the skin entry first; skin may be NULL or be
// part of model), 0 when it has none
int Q_ModelScaleLookup( const modelScaleTable_t *table, const char *model, const char *skin );

// "<min> <max>" in percent, both kept inside the hard limits; a broken string gives the default
void Q_ModelScaleParseRange( const char *str, int *outMin, int *outMax );

int Q_ModelScaleClamp( int scale, int min, int max );

#if defined(__cplusplus)
} // extern "C"
#endif
