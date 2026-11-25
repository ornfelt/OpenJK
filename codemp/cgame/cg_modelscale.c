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

// cg_modelscale.c -- player mods: what the cgame draws around a scaled player (PLAYER_MODS_STATUS.md)
//
// The model itself is drawn at its iModelScale by CG_Player, as in every JA cgame; the bbox and
// view height come from pmove (bg_modelscale.c). This file scales the rest that assumes the
// standard height.

#include "cg_local.h"
#include "cg_modelscale.h"
#include "game/bg_modelscale.h"

float CG_ModelScaleCameraFactor( void ) {
	const playerState_t *ps = &cg.predictedPlayerState;

	if ( !cg_thirdPersonModelScale.integer || ps->m_iVehicleNum || !ps->iModelScale ) {
		return 1.0f;
	}
	return ps->iModelScale / MODELSCALE_PERCENT;
}

float CG_ModelScaleAboveOrigin( const centity_t *cent, float height ) {
	if ( !cent->modelScale[2] ) {
		return height;
	}
	return height * cent->modelScale[2];
}
