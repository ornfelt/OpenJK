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

// g_playermods.c -- player mods: making the game tolerate player model mods (PLAYER_MODS_STATUS.md)

#include "g_local.h"
#include "g_playermods.h"

/*
==================
G_RepairNPCBraces

.npc entries are flat ("name { key value ... }"), so a '{' inside an entry can only be a typo for
'}' - Seven's Qui-Gon Jinn mod ships a quigon.npc with six of them. Left alone, one such file
leaves the concatenated NPC buffer unbalanced: SkipBracedSection in NPC_ParseParms then never
returns to depth 0 and every entry stored after that file (stock ones included) can't be found.

Repairs the text in place, outside quoted strings: a nested '{' becomes '}', a '}' outside an
entry becomes a space. A balanced file is not changed. Returns the number of entries still open
at the end (0 or 1).
==================
*/
int G_RepairNPCBraces( char *text, const char *fileName ) {
	int			depth = 0;
	int			fixes = 0;
	qboolean	inQuote = qfalse;
	char		*p;

	for ( p = text; *p; p++ ) {
		if ( *p == '"' ) {
			inQuote = (qboolean)!inQuote;
		} else if ( inQuote ) {
			continue;
		} else if ( *p == '{' ) {
			if ( depth > 0 ) {
				*p = '}';
				depth--;
				fixes++;
			} else {
				depth++;
			}
		} else if ( *p == '}' ) {
			if ( depth == 0 ) {
				*p = ' ';
				fixes++;
			} else {
				depth--;
			}
		}
	}

	if ( fixes || depth ) {
		Com_Printf( S_COLOR_YELLOW "WARNING: ext_data/NPCs/%s: repaired %d misplaced brace(s)%s - .npc entries cannot nest\n",
			fileName, fixes, depth ? " and a missing '}'" : "" );
	}
	return depth;
}
