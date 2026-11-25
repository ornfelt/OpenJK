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

// cg_modelscale.cpp -- player mods: the third-person camera follows the player's model size in SP
// (PLAYER_MODS_STATUS.md)

#include "cg_headers.h"

extern Vehicle_t *G_IsRidingVehicle( gentity_t *pEnt );

// the camera's range and offsets scale with the player's model size (cg_thirdPersonModelScale);
// 1 on a vehicle, while viewing through another entity or with the cvar off
float CG_ModelScaleCameraFactor( void ) {
	gentity_t *player = &g_entities[0];

	if ( !cg_thirdPersonModelScale.integer || !player->client || !cg.snap
		|| (cg.snap->ps.viewEntity > 0 && cg.snap->ps.viewEntity < ENTITYNUM_WORLD)
		|| player->client->NPC_class == CLASS_VEHICLE || G_IsRidingVehicle( player )
		|| player->s.modelScale[2] <= 0.0f ) {
		return 1.0f;
	}
	return player->s.modelScale[2];
}
