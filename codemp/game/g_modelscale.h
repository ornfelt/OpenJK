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

// g_modelscale.h -- player mods: the configurable player model size, JA++-style but built in
// (PLAYER_MODS_STATUS.md)

#pragma once

#include "bg_modelscale.h"

// loads modelscale.cfg; called once per level
void G_ModelScaleInit( void );

// a client slot was freed or taken by a new client: forget its /modelscale value
void G_ModelScaleClientReset( int clientNum );

// the client's model ("model/skin") is now this; applies the size when it changed
void G_ModelScaleUserinfoChanged( gentity_t *ent, const char *model );

// sets the client's scale, bbox and view height from the precedence (command, modelscale.cfg,
// 100); with checkFit a bigger size that doesn't fit where the client stands waits for the next
// spawn. Returns qfalse when it waited.
qboolean G_ModelScaleApply( gentity_t *ent, qboolean checkFit );

// an npc's scale: its .npc file's, else modelscale.cfg's; its bbox follows (a width / height the
// .npc file set belongs to the .npc scale, a default one to 100)
void G_ModelScaleNPC( gentity_t *npc, const char *model, const char *skin );

// the height the cgame raises the entity's scaled model by: the server's ghoul2 bolts (saber) and
// hit collision use its origin raised the same, so they match what players see. 0 when off.
float G_ModelScaleDrawOffset( const gentity_t *ent );

// g_modelScale / g_modelScaleCmd / g_modelScaleRange changed
void G_ModelScaleCvarChanged( void );

// "/modelscale [n | default]"
void Cmd_ModelScale_f( gentity_t *ent );

// the server console / rcon commands "modelscale <client> <n | default>" and "modelscales";
// qfalse when the command is not one of them (on a listen server "modelscale <n>" goes on to the
// local client)
qboolean G_ModelScaleConsoleCommand( void );
