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

// g_playerskel.h -- player mods: players on a humanoid-compatible custom skeleton, server side
// (bg_playerskel.h, PLAYER_MODS_STATUS.md)

#pragma once

#include "bg_playerskel.h"

// InitGame, before any entity or client: bgCustomSkeletons from the (latched) g_customSkeletons
void G_PlayerSkelInit( void );

// ClientUserinfoChanged with the userinfo model: qtrue when the server's ghoul2 instance of the
// client must be set up again (it moved to or from a custom skeleton, or changed model on one)
qboolean G_PlayerSkelUserinfoChanged( gentity_t *ent, const char *model );

// ClientDisconnect
void G_PlayerSkelClientReset( int clientNum );

// the client's model is on a custom skeleton (what G_PlayerHasCustomSkeleton answers)
qboolean G_PlayerSkelCustom( const gentity_t *ent );
