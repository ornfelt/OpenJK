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

// bg_playerskel.c -- player mods: player models on their own copy of the humanoid skeleton,
// shared by game and cgame (PLAYER_MODS_STATUS.md)
//
// MP only lets players use models on _humanoid.gla. A model like T_Yoda's SP model sits on its
// own .gla with the same bones and its own animation.cfg (same animation names, some of them
// remapped). Such a skeleton is "humanoid-compatible": its animation set gets its own index in
// bgAllAnims (> 1) like any other skeleton, but the "is it humanoid" checks treat it as 0.

#include "qcommon/q_shared.h"
#include "bg_public.h"
#include "bg_playerskel.h"

#ifdef _GAME
	#include "g_local.h"
#elif _CGAME
	#include "cgame/cg_local.h"
#endif

// the .gla / .glm layouts read here (rd-common/mdx_format.h): mdxaHeader_t, mdxaSkel_t, mdxmHeader_t
#define GLA_IDENT				(('A'<<24)+('G'<<16)+('L'<<8)+'2')
#define GLM_IDENT				(('M'<<24)+('G'<<16)+('L'<<8)+'2')
#define MDX_VERSION				6
#define MDX_NAME_SIZE			64
#define MDX_OFS_VERSION			4		// both headers: ident, version
#define GLA_HEADER_SIZE			100		// sizeof( mdxaHeader_t ); the bone offsets follow it
#define GLA_OFS_FRAMES			80		// mdxaHeader_t.ofsFrames: the skeleton lies before it
#define GLA_OFS_NUMBONES		84		// mdxaHeader_t.numBones
#define GLA_BONE_PARENT			68		// mdxaSkel_t.parent, after name[64] and flags
#define GLM_OFS_ANIMNAME		72		// mdxmHeader_t.animName, after ident, version, name[64]
#define GLM_HEADER_READ			(GLM_OFS_ANIMNAME + MDX_NAME_SIZE)
#define GLA_EXTENSION			".gla"

#define PLAYERSKEL_MAX_BONES	128		// more than any player skeleton (_humanoid has 53)
#define PLAYERSKEL_READ_MAX		32768	// header and skeleton of a .gla (_humanoid's: 9636 bytes)
#define PLAYERSKEL_CACHE_SIZE	32		// skeletons checked per level
#define PLAYERSKEL_LIST_SIZE	1024	// the .gla names of one skeleton dir

typedef struct playerSkel_s {
	int		numBones;
	char	names[PLAYERSKEL_MAX_BONES][MDX_NAME_SIZE];
	int		parents[PLAYERSKEL_MAX_BONES];
} playerSkel_t;

typedef struct playerSkelCache_s {
	char		glaName[MAX_QPATH];
	qboolean	compatible;
} playerSkelCache_t;

typedef enum playerSkelState_e {
	PLAYERSKEL_UNREAD,
	PLAYERSKEL_READ,
	PLAYERSKEL_FAILED
} playerSkelState_t;

qboolean bgCustomSkeletons = qfalse;

static qboolean				bgAnimSetHumanoid[MAX_ANIM_FILES];
static playerSkelCache_t	skelCache[PLAYERSKEL_CACHE_SIZE];
static int					numSkelCache;
static playerSkel_t			humanoidSkel;
static playerSkelState_t	humanoidSkelState = PLAYERSKEL_UNREAD;
static playerSkel_t			otherSkel;
static byte					skelBuf[PLAYERSKEL_READ_MAX];

static int PlayerSkel_Int( const byte *p ) {
	int value;

	memcpy( &value, p, sizeof( value ) );
	return LittleLong( value );
}

// the bone names and parents of a .gla (glaName without the extension)
static qboolean PlayerSkel_Read( const char *glaName, playerSkel_t *skel ) {
	char			path[MAX_QPATH];
	fileHandle_t	f = 0;
	int				fileLen, ofsFrames, i;

	Com_sprintf( path, sizeof( path ), "%s" GLA_EXTENSION, glaName );
	fileLen = trap->FS_Open( path, &f, FS_READ );
	if ( !f ) {
		return qfalse;
	}
	if ( fileLen < GLA_HEADER_SIZE ) {
		trap->FS_Close( f );
		return qfalse;
	}
	trap->FS_Read( skelBuf, GLA_HEADER_SIZE, f );

	ofsFrames = PlayerSkel_Int( skelBuf + GLA_OFS_FRAMES );
	skel->numBones = PlayerSkel_Int( skelBuf + GLA_OFS_NUMBONES );
	if ( PlayerSkel_Int( skelBuf ) != GLA_IDENT || PlayerSkel_Int( skelBuf + MDX_OFS_VERSION ) != MDX_VERSION
		|| skel->numBones < 1 || skel->numBones > PLAYERSKEL_MAX_BONES
		|| ofsFrames < GLA_HEADER_SIZE + skel->numBones * (int)sizeof( int )
		|| ofsFrames > PLAYERSKEL_READ_MAX || ofsFrames > fileLen ) {
		trap->FS_Close( f );
		return qfalse;
	}
	trap->FS_Read( skelBuf + GLA_HEADER_SIZE, ofsFrames - GLA_HEADER_SIZE, f );
	trap->FS_Close( f );

	for ( i = 0; i < skel->numBones; i++ ) {
		// the bone offsets are relative to the end of the header
		const int ofs = GLA_HEADER_SIZE + PlayerSkel_Int( skelBuf + GLA_HEADER_SIZE + i * sizeof( int ) );

		if ( ofs < GLA_HEADER_SIZE || ofs + GLA_BONE_PARENT + (int)sizeof( int ) > ofsFrames ) {
			return qfalse;
		}
		Q_strncpyz( skel->names[i], (const char *)skelBuf + ofs, MDX_NAME_SIZE );
		skel->parents[i] = PlayerSkel_Int( skelBuf + ofs + GLA_BONE_PARENT );
	}
	return qtrue;
}

static qboolean PlayerSkel_Same( const playerSkel_t *a, const playerSkel_t *b ) {
	int i;

	if ( a->numBones != b->numBones ) {
		return qfalse;
	}
	for ( i = 0; i < a->numBones; i++ ) {
		if ( a->parents[i] != b->parents[i] || Q_stricmp( a->names[i], b->names[i] ) ) {
			return qfalse;
		}
	}
	return qtrue;
}

qboolean BG_HumanoidCompatibleGLA( const char *glaName ) {
	qboolean	compatible;
	int			i;

	if ( !glaName || !glaName[0] ) {
		return qfalse;
	}
	if ( strstr( glaName, PLAYERSKEL_HUMANOID_DIR ) ) {
		return qtrue;
	}
	for ( i = 0; i < numSkelCache; i++ ) {
		if ( !Q_stricmp( skelCache[i].glaName, glaName ) ) {
			return skelCache[i].compatible;
		}
	}

	if ( humanoidSkelState == PLAYERSKEL_UNREAD ) {
		humanoidSkelState = PlayerSkel_Read( PLAYERSKEL_HUMANOID_GLA, &humanoidSkel ) ? PLAYERSKEL_READ : PLAYERSKEL_FAILED;
	}
	compatible = (qboolean)(humanoidSkelState == PLAYERSKEL_READ
		&& PlayerSkel_Read( glaName, &otherSkel ) && PlayerSkel_Same( &humanoidSkel, &otherSkel ));

	if ( numSkelCache < PLAYERSKEL_CACHE_SIZE ) {
		Q_strncpyz( skelCache[numSkelCache].glaName, glaName, sizeof( skelCache[numSkelCache].glaName ) );
		skelCache[numSkelCache].compatible = compatible;
		numSkelCache++;
	}
	return compatible;
}

qboolean BG_CustomHumanoidGLA( const char *glaName ) {
	return (qboolean)(bgCustomSkeletons && glaName && glaName[0]
		&& !strstr( glaName, PLAYERSKEL_HUMANOID_DIR ) && BG_HumanoidCompatibleGLA( glaName ));
}

qboolean BG_ModelHasCustomHumanoidGLA( const char *modelName, char *glaName, int glaNameSize ) {
	char			dir[MAX_QPATH], path[MAX_QPATH], animName[MDX_NAME_SIZE];
	byte			header[GLM_HEADER_READ];
	fileHandle_t	f = 0;
	int				fileLen;
	char			*slash;

	if ( !bgCustomSkeletons || !modelName || !modelName[0] ) {
		return qfalse;
	}
	Q_strncpyz( dir, modelName, sizeof( dir ) );
	slash = strchr( dir, '/' );
	if ( slash ) {
		*slash = '\0'; // "model/skin"
	}

	Com_sprintf( path, sizeof( path ), "models/players/%s/model.glm", dir );
	fileLen = trap->FS_Open( path, &f, FS_READ );
	if ( !f ) {
		return qfalse;
	}
	if ( fileLen < GLM_HEADER_READ ) {
		trap->FS_Close( f );
		return qfalse;
	}
	trap->FS_Read( header, GLM_HEADER_READ, f );
	trap->FS_Close( f );
	if ( PlayerSkel_Int( header ) != GLM_IDENT || PlayerSkel_Int( header + MDX_OFS_VERSION ) != MDX_VERSION ) {
		return qfalse;
	}

	Q_strncpyz( animName, (const char *)header + GLM_OFS_ANIMNAME, sizeof( animName ) );
	if ( !BG_CustomHumanoidGLA( animName ) ) {
		return qfalse;
	}
	if ( glaName ) {
		Q_strncpyz( glaName, animName, glaNameSize );
	}
	return qtrue;
}

void BG_PlayerSkelAnimSetLoaded( int animIndex, const char *animCfgName ) {
	char	dir[MAX_QPATH], list[PLAYERSKEL_LIST_SIZE], gla[MAX_QPATH];
	char	*slash;
	const char *first;

	if ( animIndex < 0 || animIndex >= MAX_ANIM_FILES ) {
		return;
	}
	bgAnimSetHumanoid[animIndex] = qfalse;
	if ( !bgCustomSkeletons ) {
		return;
	}

	Q_strncpyz( dir, animCfgName, sizeof( dir ) );
	slash = Q_strrchr( dir, '/' );
	if ( !slash ) {
		return;
	}
	*slash = '\0';

	// the skeleton next to the animation.cfg: the first .gla of its dir (a skeleton dir holds one)
	if ( trap->FS_GetFileList( dir, GLA_EXTENSION, list, sizeof( list ) ) < 1 ) {
		return;
	}
	first = list[0] == '/' ? list + 1 : list;
	Com_sprintf( gla, sizeof( gla ), "%s/%s", dir, first );
	COM_StripExtension( gla, gla, sizeof( gla ) );

	bgAnimSetHumanoid[animIndex] = BG_HumanoidCompatibleGLA( gla );
}

int BG_HumanoidAnimIndex( int animIndex ) {
	if ( bgCustomSkeletons && animIndex > 1 && animIndex < MAX_ANIM_FILES && bgAnimSetHumanoid[animIndex] ) {
		return 0;
	}
	return animIndex;
}
