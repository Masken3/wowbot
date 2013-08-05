#include <inttypes.h>
#include <stdio.h>
#include "log.h"
#include "dumpPacket.h"

void dumpPacket(const char* buf, size_t bufSize) {
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

void dumpBinaryFile(const char* filename, const void* buf, size_t bufSize) {
	FILE* f = fopen(filename, "wb");
	fwrite(buf, bufSize, 1, f);
	fclose(f);
	LOG("dumped file %s\n", filename);
}
