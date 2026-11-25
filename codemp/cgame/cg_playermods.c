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

// cg_playermods.c -- player mods: making the cgame tolerate player model mods (PLAYER_MODS_STATUS.md)

#include "cg_local.h"
#include "cg_playermods.h"

#define MIN_SOUND_DIR_LEN	2	// a one-letter line is the gender marker ("m" / "f")

// the length of the line at text when it is one word (a sound dir), else 0
static int CG_SoundDirLineLength( const char *text ) {
	int len = 0;

	while ( text[len] && text[len] != '\r' && text[len] != '\n' ) {
		if ( text[len] == ' ' || text[len] == '\t' || text[len] == '"' ) {
			return 0;
		}
		len++;
	}
	return len;
}

/*
==================
CG_PickSoundsCfgDir

models/players/<model>/sounds.cfg holds the sound dir (sound/chars/<dir>) on its first line and
an optional gender line. themando_doughnuts' dindjarin/sounds.cfg starts with an SP-style
'breathes "0"' line instead, so the sound dir became 'breathes "0"' and every sound fell back.
A sound dir is one word: when the first line is not, the first later one-word line (longer than
the gender marker) is moved to the front. A valid file is not changed.
==================
*/
void CG_PickSoundsCfgDir( char *text ) {
	char	*line;
	int		len;

	if ( !text[0] || CG_SoundDirLineLength( text ) ) {
		return;
	}

	for ( line = strchr( text, '\n' ); line; line = strchr( line, '\n' ) ) {
		line++;
		len = CG_SoundDirLineLength( line );
		if ( len >= MIN_SOUND_DIR_LEN ) {
			memmove( text, line, strlen( line ) + 1 );
			return;
		}
	}
}
