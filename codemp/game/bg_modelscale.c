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

// bg_modelscale.c -- player mods: the scaled player bbox, shared by game and cgame; the
// modelscale.cfg parser is shared/qcommon/q_modelscale.c (PLAYER_MODS_STATUS.md)

#include "qcommon/q_shared.h"
#include "bg_public.h"
#include "bg_modelscale.h"

float BG_ModelScaleFactor( const playerState_t *ps, qboolean enabled ) {
	if ( !enabled || ps->clientNum >= MAX_CLIENTS || !ps->iModelScale || ps->iModelScale == MODELSCALE_DEFAULT ) {
		return 1.0f;
	}
	return ps->iModelScale / MODELSCALE_PERCENT;
}

float BG_ModelScaleZ( float z, float factor ) {
	if ( factor == 1.0f ) {
		return z;
	}
	return MINS_Z + (z - MINS_Z) * factor;
}

int BG_ModelScaleViewHeight( int viewHeight, float factor ) {
	if ( factor == 1.0f ) {
		return viewHeight;
	}
	return (int)floorf( BG_ModelScaleZ( (float)viewHeight, factor ) + 0.5f );
}

float BG_ModelScaleHalfWidth( float factor ) {
	return MODELSCALE_HALF_WIDTH * factor;
}

float BG_ModelScaleDrawOffset( float factor ) {
	return -MINS_Z * (factor - 1.0f);
}
