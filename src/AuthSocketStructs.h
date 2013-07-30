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

typedef struct AUTH_LOGON_PROOF_S
{
	uint8   cmd;
	uint8   error;
	uint8   M2[20];
	uint32  accountFlags;                                   // see enum AccountFlags
	uint32  surveyId;                                       // SurveyId
	uint16  unkFlags;                                       // some flags (AccountMsgAvailable = 0x01)
} sAuthLogonProof_S;

#if defined( __GNUC__ )
#pragma pack()
#else
#pragma pack(pop)
#endif

#endif	//AUTHSOCKETSTRUCTS_H
