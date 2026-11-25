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

// g_playermods.h -- player mods: making the game tolerate player model mods (PLAYER_MODS_STATUS.md)

#pragma once

// repairs the braces of one compressed .npc file in place; returns the entries still open at its
// end (0 or 1), which the caller closes with a '}'
int G_RepairNPCBraces( char *text, const char *fileName );
