#ifndef TYPES_H
#define TYPES_H

typedef unsigned int uint;
typedef uint16_t ushort;
typedef uint8_t byte;

#ifndef BOOL
typedef int BOOL;
enum {
	FALSE = 0,
	TRUE = 1,
};
#endif

#endif	//TYPES_H
