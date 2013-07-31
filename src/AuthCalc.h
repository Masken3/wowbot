#include "AuthSocketStructs.h"

#ifdef __cplusplus
extern "C"
#endif
void CalculateLogonProof(sAuthLogonChallenge_S* lcs, sAuthLogonProof_C* lpc,
	const char* username, const char* password, uint8* M2, uint8* K);
