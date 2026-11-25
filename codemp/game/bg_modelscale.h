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

#include "qcommon/q_modelscale.h"

// the serverinfo key telling clients that pmove scales the player bbox and view height
#define MODELSCALE_SERVERINFO_KEY	"g_modelScale"

#define MODELSCALE_HALF_WIDTH		15		// a player's bbox half width at scale 100 (bg_pmove.c)

// the size factor pmove applies to a player: 1 unless enabled and a client with a scale
float BG_ModelScaleFactor( const playerState_t *ps, qboolean enabled );

// a height above the origin (maxs[2], a view height) scaled with the feet kept at MINS_Z, the way
// the cgame draws a scaled player (CG_Player raises the model by 24 * (scale - 1))
float BG_ModelScaleZ( float z, float factor );
int BG_ModelScaleViewHeight( int viewHeight, float factor );
float BG_ModelScaleHalfWidth( float factor );

// how far CG_Player raises a scaled (non-vehicle) model above its origin: 24 * (factor - 1)
float BG_ModelScaleDrawOffset( float factor );
