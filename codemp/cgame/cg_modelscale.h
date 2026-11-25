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

// cg_modelscale.h -- player mods: what the cgame draws around a scaled player (PLAYER_MODS_STATUS.md)

#pragma once

// the third-person camera's range and offsets scale with the viewed player's model size
// (cg_thirdPersonModelScale); 1 on a vehicle, for an unscaled player or with the cvar off
float CG_ModelScaleCameraFactor( void );

// a height above a drawn player's origin (a sprite over its head) for the player's model size;
// CG_Player has already raised lerpOrigin by 24 * (scale - 1) to keep the feet on the ground
float CG_ModelScaleAboveOrigin( const centity_t *cent, float height );
