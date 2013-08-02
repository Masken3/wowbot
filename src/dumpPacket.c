#include <inttypes.h>
#include "log.h"
#include "dumpPacket.h"

void dumpPacket(char* buf, size_t bufSize) {
	// assume 80-char wide output
	LOG("%" PRIuPTR " bytes:\n", bufSize);
	for(size_t i=0; i<bufSize; i++) {
		LOG("%02x ", (unsigned char)buf[i]);
		if(!((i+1) & 0x7)) {
			LOG(" ");
		}
		if(!((i+1) & 0xf)) {
			LOG("\n");
		}
	}
	LOG("\n");
}
