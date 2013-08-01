#include <inttypes.h>

#include "socket.h"
#include "config.h"
#include "Common.h"
#include "world.h"
#include "Opcodes.h"
#include <assert.h>
#include "WorldCrypt.h"
#include "worldHandlers.h"
#include "log.h"
#include "SharedDefines.h"

#include "hChar.h"

#if defined( __GNUC__ )
#pragma pack(1)
#else
#pragma pack(push,1)
#endif

struct Equipment {
	uint32 displayInfoId;
	uint8 inventoryType;
};

typedef struct sSMSG_CHAR_ENUM_ENTRY {
	//uint64 guid;
	//const char* name;
	uint8 race;
	uint8 _class;
	uint8 gender;

	uint8 skin;
	uint8 face;
	uint8 hairStyle;
	uint8 hairColor;

	uint8 facialHair;

	uint8 level;
	uint32 zone;
	uint32 map;

	float x, y, z;

	uint32 guild;

	uint32 flags;

	// First login
	uint8 firstLogin;

	uint32 petDisplayId;
	uint32 petLevel;
	uint32 petFamily;

	struct Equipment equipment[EQUIPMENT_SLOT_END];

	uint32 firstBagDisplayId;
	uint8 firstBagInventoryType;
} sSMSG_CHAR_ENUM_ENTRY;

typedef struct sCMSG_CHAR_CREATE {
	uint8 race;
	uint8 _class;
	uint8 gender, skin, face, hairStyle, hairColor, facialHair, outfitId;
} sCMSG_CHAR_CREATE;

#if defined( __GNUC__ )
#pragma pack()
#else
#pragma pack(pop)
#endif

#define TOON_NAME "Warrior"

static void createToon(WorldSession* session) {
	char buf[1024];
	sCMSG_CHAR_CREATE c;

	memset(&c, 0, sizeof(c));
	c.race = RACE_DWARF;
	c._class = CLASS_WARRIOR;
	c.gender = 0;

	strcpy(buf, TOON_NAME);
	memcpy(buf + sizeof(TOON_NAME), &c, sizeof(c));

	sendWorld(session, CMSG_CHAR_CREATE, buf, sizeof(TOON_NAME) + sizeof(c));
}

static void enterWorld(WorldSession* session, uint64 guid) {
	sendWorld(session, CMSG_PLAYER_LOGIN, &guid, sizeof(guid));
}

void hSMSG_CHAR_ENUM(WorldSession* session, char* buf, uint16 size) {
	uint8 num = buf[0];
	LOG("%i toons:\n", num);

	if(num == 0) {
		createToon(session);
		// hSMSG_CHAR_CREATE will enterWorld.
	} else {
		char* ptr = buf+1;
		for(uint8 i=0; i<num; i++) {
			sSMSG_CHAR_ENUM_ENTRY* e;
			const char* name;
			uint64 guid = *(uint64*)ptr;
			ptr += 8;
			name = ptr;
			ptr += strlen(name) + 1;
			e = (sSMSG_CHAR_ENUM_ENTRY*)ptr;
			LOG("%i: 0x%" PRIx64 " %s r%i c%i g%i\n",
				i, guid, name, e->race, e->_class, e->gender);
			if(i == 0) {
				enterWorld(session, guid);
			}
		}
	}
}

void hSMSG_CHAR_CREATE(WorldSession* session, char* buf, uint16 size) {
	uint8 res = buf[0];
	if(res == CHAR_CREATE_SUCCESS) {
		LOG("CHAR_CREATE_SUCCESS\n");
		sendWorld(session, CMSG_CHAR_ENUM, NULL, 0);
	} else {
		LOG("CHAR_CREATE_ERROR: %i\n", res);
	}
}
