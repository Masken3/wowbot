#include <stdio.h>

#define LOG printf

#define DUMPINT(i) LOG("%s: %i\n", #i, i)
#define DUMPSTR(i) LOG("%s: %s\n", #i, i)
