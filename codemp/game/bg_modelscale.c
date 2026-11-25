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

// bg_modelscale.c -- player mods: the modelscale.cfg parser and the scaled player bbox, shared by
// game and cgame (PLAYER_MODS_STATUS.md)

#include "qcommon/q_shared.h"
#include "bg_public.h"
#include "bg_modelscale.h"

#define MODELSCALE_TOKEN_SIZE	MAX_QPATH

// skips whitespace and comments; returns the start of the next token or the end of the text
static const char *BG_ModelScaleSkip( const char *p ) {
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
static const char *BG_ModelScaleToken( const char *p, char *out, int outSize ) {
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
static int BG_ModelScaleFactorToPercent( const char *token ) {
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

static modelScaleEntry_t *BG_ModelScaleFind( modelScaleTable_t *table, const char *model ) {
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
BG_ModelScaleParse

Adds the "model scale" pairs of text to table; returns the number of pairs read. A pair whose
scale is not a positive number is skipped with a warning, a scale outside the hard limits is
clamped with one.
==================
*/
int BG_ModelScaleParse( modelScaleTable_t *table, const char *text, const char *fileName ) {
	char				model[MODELSCALE_TOKEN_SIZE], value[MODELSCALE_TOKEN_SIZE];
	const char			*p = text;
	int					pairs = 0, scale;
	modelScaleEntry_t	*entry;

	for ( ;; ) {
		p = BG_ModelScaleSkip( p );
		if ( !*p ) {
			break;
		}
		p = BG_ModelScaleToken( p, model, sizeof( model ) );
		p = BG_ModelScaleSkip( p );
		if ( !*p ) {
			Com_Printf( S_COLOR_YELLOW "WARNING: %s: model '%s' has no scale\n", fileName, model );
			break;
		}
		p = BG_ModelScaleToken( p, value, sizeof( value ) );

		scale = BG_ModelScaleFactorToPercent( value );
		if ( scale <= 0 ) {
			Com_Printf( S_COLOR_YELLOW "WARNING: %s: bad scale '%s' for model '%s'\n", fileName, value, model );
			continue;
		}
		if ( scale < MODELSCALE_HARD_MIN || scale > MODELSCALE_HARD_MAX ) {
			Com_Printf( S_COLOR_YELLOW "WARNING: %s: scale %s for model '%s' clamped to %d-%d%%\n", fileName, value, model,
				MODELSCALE_HARD_MIN, MODELSCALE_HARD_MAX );
			scale = BG_ModelScaleClamp( scale, MODELSCALE_HARD_MIN, MODELSCALE_HARD_MAX );
		}

		entry = BG_ModelScaleFind( table, model );
		if ( !entry ) {
			if ( table->numEntries >= MODELSCALE_MAX_ENTRIES ) {
				Com_Printf( S_COLOR_YELLOW "WARNING: %s: more than %d models, the rest are ignored\n", fileName, MODELSCALE_MAX_ENTRIES );
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

int BG_ModelScaleLookup( const modelScaleTable_t *table, const char *model, const char *skin ) {
	char	key[MAX_QPATH];
	char	*slash;
	int		i;

	// "model/skin" as one string (userinfo) or apart (npc playerModel + customSkin)
	Q_strncpyz( key, model, sizeof( key ) );
	if ( skin && skin[0] && !strchr( key, '/' ) ) {
		Q_strcat( key, sizeof( key ), va( "/%s", skin ) );
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

void BG_ModelScaleParseRange( const char *str, int *outMin, int *outMax ) {
	int min = 0, max = 0;

	if ( !str || sscanf( str, "%d %d", &min, &max ) != 2 || min <= 0 || max < min ) {
		sscanf( MODELSCALE_RANGE_DEFAULT, "%d %d", &min, &max );
	}
	*outMin = BG_ModelScaleClamp( min, MODELSCALE_HARD_MIN, MODELSCALE_HARD_MAX );
	*outMax = BG_ModelScaleClamp( max, MODELSCALE_HARD_MIN, MODELSCALE_HARD_MAX );
}

int BG_ModelScaleClamp( int scale, int min, int max ) {
	if ( scale < min ) {
		return min;
	}
	if ( scale > max ) {
		return max;
	}
	return scale;
}

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
