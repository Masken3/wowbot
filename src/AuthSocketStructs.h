#include <stdint.h>
typedef uint8_t uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;

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

typedef struct AUTH_LOGON_PROOF_C
{
	uint8   cmd;
	uint8   A[32];
	uint8   M1[20];
	uint8   crc_hash[20];
	uint8   number_of_keys;
	uint8   securityFlags;                                  // 0x00-0x04
} sAuthLogonProof_C;

#if defined( __GNUC__ )
#pragma pack()
#else
#pragma pack(pop)
#endif
