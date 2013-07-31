#ifndef CONFIGFILE_H
#define CONFIGFILE_H

typedef const char* cs;

// creates a character if one with that name does not exist.
// logs in if a matching character exists.
// aborts if a character with matching name but mismatching race/class/gender exists.
typedef struct Toon {
	cs accountName;
	cs password;
	cs name;
	enum Race race;
	enum Class _class;
	enum Gender gender;
};

typedef struct Config {
	cs realmName;
	int toonCount;
	Toon* toons;
} Config;

#endif	//CONFIGFILE_H
