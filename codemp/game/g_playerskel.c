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

// g_playerskel.c -- player mods: players on a humanoid-compatible custom skeleton, server side
// (bg_playerskel.c, PLAYER_MODS_STATUS.md)
//
// Such a player gets its own server ghoul2 instance (G_PlayerHasCustomSkeleton, like the
// commented-out siege custom skeletons) so its animation frames, bolts and collision match its
// .gla, and its own animation set (SetupGameGhoul2Model). The cgame does the same from the
// serverinfo key; nothing new goes over the network.

#include "g_local.h"
#include "g_playerskel.h"

static qboolean	playerSkelCustom[MAX_CLIENTS];
static char		playerSkelModel[MAX_CLIENTS][MAX_QPATH];

void G_PlayerSkelInit( void ) {
	bgCustomSkeletons = (qboolean)(g_customSkeletons.integer != 0);
	memset( playerSkelCustom, 0, sizeof( playerSkelCustom ) );
	memset( playerSkelModel, 0, sizeof( playerSkelModel ) );
}

qboolean G_PlayerSkelUserinfoChanged( gentity_t *ent, const char *model ) {
	const int	clientNum = ent->s.number;
	char		glaName[MAX_QPATH];
	qboolean	custom, changed;

	if ( clientNum < 0 || clientNum >= MAX_CLIENTS ) {
		return qfalse;
	}

	custom = BG_ModelHasCustomHumanoidGLA( model, glaName, sizeof( glaName ) );
	changed = (qboolean)(custom != playerSkelCustom[clientNum]
		|| (custom && Q_stricmp( model, playerSkelModel[clientNum] )));

	if ( changed && custom ) {
		trap->Print( "player mods: client %d model %s uses its own skeleton %s\n", clientNum, model, glaName );
	}
	playerSkelCustom[clientNum] = custom;
	Q_strncpyz( playerSkelModel[clientNum], custom ? model : "", sizeof( playerSkelModel[clientNum] ) );
	return changed;
}

void G_PlayerSkelClientReset( int clientNum ) {
	if ( clientNum < 0 || clientNum >= MAX_CLIENTS ) {
		return;
	}
	playerSkelCustom[clientNum] = qfalse;
	playerSkelModel[clientNum][0] = '\0';
}

qboolean G_PlayerSkelCustom( const gentity_t *ent ) {
	return (qboolean)(ent && ent->s.number >= 0 && ent->s.number < MAX_CLIENTS && playerSkelCustom[ent->s.number]);
}
