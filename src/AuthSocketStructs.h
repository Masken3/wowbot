#ifndef AUTHSOCKETSTRUCTS_H
#define AUTHSOCKETSTRUCTS_H

#include "Common.h"

// copied from AuthSocket.cpp

#if defined( __GNUC__ )
#pragma pack(1)
#else
#pragma pack(push,1)
#endif

typedef struct AUTH_LOGON_CHALLENGE_C
{
	uint8   cmd;
	uint8   error;
	uint16  size;
	uint8   gamename[4];
	uint8   version1;
	uint8   version2;
	uint8   version3;
	uint16  build;
	uint8   platform[4];
	uint8   os[4];
	uint8   country[4];
	uint32  timezone_bias;
	uint32  ip;
	uint8   I_len;
	uint8   I[1];
} sAuthLogonChallenge_C;

typedef struct
{
	uint8   cmd;
	uint8   error;
	uint8   unk2;
	uint8   B[32];
	uint8   g_len;
	uint8   g[1];
	uint8   N_len;
	uint8   N[32];
	uint8   s[32];
	uint8   unk3[16];
	uint8   unk4;
} sAuthLogonChallenge_S;

typedef struct AUTH_LOGON_PROOF_C
{
	uint8   cmd;
	uint8   A[32];
	uint8   M1[20];
	uint8   crc_hash[20];
	uint8   number_of_keys;
	uint8   securityFlags;                                  // 0x00-0x04
} sAuthLogonProof_C;

typedef struct AUTH_LOGON_PROOF_S1
{
	uint8   cmd;
	uint8   error;
} sAuthLogonProof_S1;

typedef struct AUTH_LOGON_PROOF_S2
{
	uint8   M2[20];                                         // this part sent only if s1.error = 0.
	uint32  accountFlags;                                   // see enum AccountFlags
} sAuthLogonProof_S2;

typedef struct AUTH_REALM_HEADER_S
{
	uint8   cmd;
	uint16  size;
	uint32 unk;
	uint8 count;
} sAuthRealmHeader_S;

typedef struct AUTH_REALM_FOOTER_S
{
	uint16 unk2;
} sAuthRealmFooter_S;

// Realm entry has three parts:
// entry1, 2 zero-terminated strings (name & address), entry2.

typedef struct AUTH_REALM_ENTRY1_S
{
	uint32 icon;
	uint8 flags;
} sAuthRealmEntry1_S;

// name
// address

typedef struct AUTH_REALM_ENTRY2_S
{
	float popLevel;
	uint8 charCount;
	uint8 timezone;
	uint8 unk;
} sAuthRealmEntry2_S;

#if defined( __GNUC__ )
#pragma pack()
#else
#pragma pack(pop)
#endif

enum AccountTypes
{
	SEC_PLAYER         = 0,
	SEC_MODERATOR      = 1,
	SEC_GAMEMASTER     = 2,
	SEC_ADMINISTRATOR  = 3,
	SEC_CONSOLE        = 4,	// must be always last in list, accounts must have less security level always also
};

// Used in mangosd/realmd
enum RealmFlags
{
	REALM_FLAG_NONE         = 0x00,
	REALM_FLAG_INVALID      = 0x01,
	REALM_FLAG_OFFLINE      = 0x02,
	REALM_FLAG_SPECIFYBUILD = 0x04,	// client will show realm version in RealmList screen in form "RealmName (major.minor.revision.build)"
	REALM_FLAG_UNK1         = 0x08,
	REALM_FLAG_UNK2         = 0x10,
	REALM_FLAG_NEW_PLAYERS  = 0x20,
	REALM_FLAG_RECOMMENDED  = 0x40,
	REALM_FLAG_FULL         = 0x80,
};

#endif	//AUTHSOCKETSTRUCTS_H
