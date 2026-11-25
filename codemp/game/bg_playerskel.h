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

// bg_playerskel.h -- player mods: player models on their own copy of the humanoid skeleton (a .gla
// with exactly the bones of _humanoid.gla, like T_Yoda's _humanoid_yoda), shared by game and
// cgame (PLAYER_MODS_STATUS.md)

#pragma once

#include "qcommon/q_shared.h"

// the serverinfo key (and server cvar) telling clients that the server runs such player models
// on their own skeleton and animation.cfg
#define PLAYERSKEL_SERVERINFO_KEY	"g_customSkeletons"

// the stock skeleton every player model must use without this (a G2API_GetGLAName substring)
#define PLAYERSKEL_HUMANOID_DIR		"players/_humanoid/"
#define PLAYERSKEL_HUMANOID_GLA		"models/players/_humanoid/_humanoid"

// set from g_customSkeletons (game) or the serverinfo key (cgame); off = the stock behaviour
extern qboolean bgCustomSkeletons;

// glaName as G2API_GetGLAName gives it (no extension): the .gla has the bones of _humanoid.gla,
// same count, names and parents in the same order; _humanoid itself is compatible
qboolean BG_HumanoidCompatibleGLA( const char *glaName );

// enabled, not the stock _humanoid skeleton, and compatible with it
qboolean BG_CustomHumanoidGLA( const char *glaName );

// a player model dir ("t_yoda", "t_yoda/default") whose model.glm is on such a custom skeleton;
// glaName (may be NULL) receives the skeleton's name
qboolean BG_ModelHasCustomHumanoidGLA( const char *modelName, char *glaName, int glaNameSize );

// called by BG_ParseAnimationFile for every new non-humanoid animation set: remembers whether its
// skeleton (the .gla next to animCfgName) is humanoid-compatible
void BG_PlayerSkelAnimSetLoaded( int animIndex, const char *animCfgName );

// the index the "is it humanoid" checks compare (0 humanoid, 1 rockettrooper, > 1 other
// skeletons): 0 for an animation set on a humanoid-compatible custom skeleton while enabled,
// animIndex otherwise
int BG_HumanoidAnimIndex( int animIndex );
