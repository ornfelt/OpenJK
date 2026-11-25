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

// g_modelscale.h -- player mods: the configurable player model size in SP, JA++-style but built in
// (PLAYER_MODS_STATUS.md)

#pragma once

#include "qcommon/q_modelscale.h"

// registers the cvars and loads modelscale.cfg; called once per level
void G_ModelScaleInit( void );

// applies a cvar change (g_modelScale, g_modelScaleCmd, g_modelScaleRange) to the player
void G_ModelScaleRunFrame( void );

// a client entity (the player or an npc) got its model. model / skin as known (model NULL: taken
// from its ghoul2 model), npcScale the .npc file's scale in percent (MODELSCALE_DEFAULT when none),
// bboxFromNpc: NPC_ParseParms just set the bbox (a default one is scaled, a sized one kept);
// qfalse: the bbox goes back to the default first
void G_ModelScaleSetModel( gentity_t *ent, const char *model, const char *skin, int npcScale, qboolean bboxFromNpc );

// an entityState modelScale factor in whole percent
int G_ModelScalePercent( float factor );

// "modelscale [n | default]" and "modelscales" (console commands, no cheats needed)
void Svcmd_ModelScale_f( void );
void Svcmd_ModelScales_f( void );
