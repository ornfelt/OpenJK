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

// q_modelscale.c -- player mods: the modelscale.cfg parser, shared by the SP and MP game modules and
// the MP cgame (PLAYER_MODS_STATUS.md). Plain C, no game types: each game passes its own print.

#include "q_modelscale.h"
#include "q_string.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MODELSCALE_TOKEN_SIZE	MODELSCALE_MODEL_SIZE

// skips whitespace and comments; returns the start of the next token or the end of the text
static const char *Q_ModelScaleSkip( const char *p ) {
	for ( ;; ) {
		while ( *p && (unsigned char)*p <= ' ' ) {
			p++;
		}
		if ( p[0] == '/' && p[1] == '/' ) {
			while ( *p && *p != '\n' ) {
				p++;
			}
		} else if ( p[0] == '/' && p[1] == '*' ) {
			p += 2;
			while ( *p && !(p[0] == '*' && p[1] == '/') ) {
				p++;
			}
			if ( *p ) {
				p += 2;
			}
		} else {
			return p;
		}
	}
}

// copies the token at p (up to whitespace or a comment) into out; returns the text after it
static const char *Q_ModelScaleToken( const char *p, char *out, int outSize ) {
	int len = 0;

	while ( *p && (unsigned char)*p > ' ' && !(p[0] == '/' && (p[1] == '/' || p[1] == '*')) ) {
		if ( len < outSize - 1 ) {
			out[len++] = *p;
		}
		p++;
	}
	out[len] = '\0';
	return p;
}

// a factor as written in the file ("0.5", "1", ".95") in whole percent, 0 when it isn't one
static int Q_ModelScaleFactorToPercent( const char *token ) {
	const char	*c;
	int			digits = 0, dots = 0;
	float		factor;

	for ( c = token; *c; c++ ) {
		if ( *c >= '0' && *c <= '9' ) {
			digits++;
		} else if ( *c == '.' ) {
			dots++;
		} else {
			return 0;
		}
	}
	if ( !digits || dots > 1 ) {
		return 0;
	}
	factor = atof( token );
	return (int)floorf( factor * MODELSCALE_PERCENT + 0.5f );
}

static modelScaleEntry_t *Q_ModelScaleFind( modelScaleTable_t *table, const char *model ) {
	int i;

	for ( i = 0; i < table->numEntries; i++ ) {
		if ( !Q_stricmp( table->entries[i].model, model ) ) {
			return &table->entries[i];
		}
	}
	return NULL;
}

/*
==================
Q_ModelScaleParse

Adds the "model scale" pairs of text to table; returns the number of pairs read. A pair whose
scale is not a positive number is skipped with a warning, a scale outside the hard limits is
clamped with one.
==================
*/
int Q_ModelScaleParse( modelScaleTable_t *table, const char *text, const char *fileName, modelScalePrint_t print ) {
	char				model[MODELSCALE_TOKEN_SIZE], value[MODELSCALE_TOKEN_SIZE];
	const char			*p = text;
	int					pairs = 0, scale;
	modelScaleEntry_t	*entry;

	for ( ;; ) {
		p = Q_ModelScaleSkip( p );
		if ( !*p ) {
			break;
		}
		p = Q_ModelScaleToken( p, model, sizeof( model ) );
		p = Q_ModelScaleSkip( p );
		if ( !*p ) {
			print( "^3WARNING: %s: model '%s' has no scale\n", fileName, model );
			break;
		}
		p = Q_ModelScaleToken( p, value, sizeof( value ) );

		scale = Q_ModelScaleFactorToPercent( value );
		if ( scale <= 0 ) {
			print( "^3WARNING: %s: bad scale '%s' for model '%s'\n", fileName, value, model );
			continue;
		}
		if ( scale < MODELSCALE_HARD_MIN || scale > MODELSCALE_HARD_MAX ) {
			print( "^3WARNING: %s: scale %s for model '%s' clamped to %d-%d%%\n", fileName, value, model,
				MODELSCALE_HARD_MIN, MODELSCALE_HARD_MAX );
			scale = Q_ModelScaleClamp( scale, MODELSCALE_HARD_MIN, MODELSCALE_HARD_MAX );
		}

		entry = Q_ModelScaleFind( table, model );
		if ( !entry ) {
			if ( table->numEntries >= MODELSCALE_MAX_ENTRIES ) {
				print( "^3WARNING: %s: more than %d models, the rest are ignored\n", fileName, MODELSCALE_MAX_ENTRIES );
				break;
			}
			entry = &table->entries[table->numEntries++];
			Q_strncpyz( entry->model, model, sizeof( entry->model ) );
		}
		entry->scale = scale;
		pairs++;
	}
	return pairs;
}

int Q_ModelScaleLookup( const modelScaleTable_t *table, const char *model, const char *skin ) {
	char	key[MODELSCALE_MODEL_SIZE];
	char	*slash;
	int		i;

	// "model/skin" as one string (userinfo) or apart (npc playerModel + customSkin)
	Q_strncpyz( key, model, sizeof( key ) );
	if ( skin && skin[0] && !strchr( key, '/' ) ) {
		Q_strcat( key, sizeof( key ), "/" );
		Q_strcat( key, sizeof( key ), skin );
	}

	for ( i = 0; i < table->numEntries; i++ ) {
		if ( !Q_stricmp( table->entries[i].model, key ) ) {
			return table->entries[i].scale;
		}
	}

	slash = strchr( key, '/' );
	if ( !slash ) {
		return 0;
	}
	*slash = '\0';
	for ( i = 0; i < table->numEntries; i++ ) {
		if ( !Q_stricmp( table->entries[i].model, key ) ) {
			return table->entries[i].scale;
		}
	}
	return 0;
}

void Q_ModelScaleParseRange( const char *str, int *outMin, int *outMax ) {
	int min = 0, max = 0;

	if ( !str || sscanf( str, "%d %d", &min, &max ) != 2 || min <= 0 || max < min ) {
		sscanf( MODELSCALE_RANGE_DEFAULT, "%d %d", &min, &max );
	}
	*outMin = Q_ModelScaleClamp( min, MODELSCALE_HARD_MIN, MODELSCALE_HARD_MAX );
	*outMax = Q_ModelScaleClamp( max, MODELSCALE_HARD_MIN, MODELSCALE_HARD_MAX );
}

int Q_ModelScaleClamp( int scale, int min, int max ) {
	if ( scale < min ) {
		return min;
	}
	if ( scale > max ) {
		return max;
	}
	return scale;
}
