#include <stdint.h>
typedef uint8_t uint8;

// copied from AuthSocket.cpp

typedef struct AUTH_LOGON_PROOF_C
{
	uint8   cmd;
	uint8   A[32];
	uint8   M1[20];
	uint8   crc_hash[20];
	uint8   number_of_keys;
	uint8   securityFlags;                                  // 0x00-0x04
} sAuthLogonProof_C;
