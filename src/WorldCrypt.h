#ifndef WORLDCRYPT_H
#define WORLDCRYPT_H

#include "WorldSocketStructs.h"

#ifdef __cplusplus
extern "C"
#endif
void decryptHeader(WorldSession*, ServerPktHeader*);

#ifdef __cplusplus
extern "C"
#endif
void initCrypto(WorldSession*);

#endif	//WORLDCRYPT_H
