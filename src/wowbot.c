#include "config.h"
#include "socket.h"
#include "AuthCodes.h"
#include "AuthSocketStructs.h"
#include "AuthCalc.h"
#include "log.h"
#include "world.h"
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <assert.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#define DEFAULT_WORLDSERVER_PORT 8085                       //8129
#define DEFAULT_REALMSERVER_PORT 3724

typedef uint16_t ushort;
typedef uint8_t byte;

static Socket connectNewSocket(const char* address, ushort port);
static char* dumpRealmList(Socket, const char* targetRealmName);
static void authenticate(Socket, WorldSession*);
static void connectToWorld(WorldSession*, Socket authSock, const char* realmName);

int main(void) {
	Socket authSock;
	WorldSession session;
	lua_State* L;
	int res;

	L = luaL_newstate();
	luaL_openlibs(L);
	res = luaL_loadfile(L, "src/wowbot.lua");
	if(res != LUA_OK) {
		LOG("LUA load error!\n");
		LOG("%s\n", lua_tostring(L, -1));
		exit(1);
	}
	res = lua_pcall(L, 0, 0, 0);
	if(res != LUA_OK) {
		LOG("LUA run error!\n");
		LOG("%s\n", lua_tostring(L, -1));
		exit(1);
	}
	session.L = L;

	worldCheckLua(&session);

#ifdef WIN32
	{
		// Initialize Winsock
		WSADATA wsaData;
		res = WSAStartup(MAKEWORD(2,2), &wsaData);
		if (res != 0) {
			printf("WSAStartup failed: %d\n", res);
			exit(1);
		}
	}
#endif

	LOG("Connecting...\n");
	authSock = connectNewSocket(CONFIG_SERVER_ADDRESS, DEFAULT_REALMSERVER_PORT);
	if(authSock == INVALID_SOCKET) {
		exit(1);
	}
	LOG("Connected.\n");

	authenticate(authSock, &session);
	if(1) {//config.realmName) {
		connectToWorld(&session, authSock, "Plain");
		runWorld(&session);
	} else {
		dumpRealmList(authSock, NULL);
	}

	return 0;
}

#if 0
static void sendAndReceiveDump(Socket sock, const char* buf, size_t size) {
	int res;
	res = send(sock, buf, size, 0);
	if(SOCKET_ERROR == res)
	{
		LOG("send() returned error code %d\n", SOCKET_ERRNO);
		exit(1);
	}
	LOG("recv...\n");
	do {
		char recvbuf[1024];
		res = recv(sock, recvbuf, sizeof(recvbuf), 0);
		if (res > 0)
			printf("Bytes received: %d\n", res);
		else if (res == 0)
			printf("Connection closed\n");
		else
			printf("recv failed: %d\n", SOCKET_ERRNO);
		return;
	} while (res > 0);
}
#endif

static void authenticate(Socket sock, WorldSession* session) {
	sAuthLogonChallenge_S lcs;
	sAuthLogonProof_C lpc;
	sAuthLogonProof_S lps;
	byte M2[20];
	// send & receive challenge
	{
		char buf[1024];
		sAuthLogonChallenge_C* lcc = (sAuthLogonChallenge_C*)buf;
		memset(lcc, 0, sizeof(*lcc));
		lcc->cmd = CMD_AUTH_LOGON_CHALLENGE;
		lcc->I_len = sizeof(CONFIG_ACCOUNT_NAME);
		lcc->size = sizeof(*lcc) + (lcc->I_len - 1) - 4;
		lcc->build = 5875;	// client version 1.12.1
		strcpy((char*)lcc->I, CONFIG_ACCOUNT_NAME);
		sendAndReceiveExact(sock, buf, lcc->size + 4, &lcs, sizeof(lcs));
	}
	// calculate proof
	CalculateLogonProof(&lcs, &lpc, CONFIG_ACCOUNT_NAME, CONFIG_ACCOUNT_PASSWORD, M2, session->key);
	// send proof
	{
		lpc.cmd = CMD_AUTH_LOGON_PROOF;
		sendAndReceiveExact(sock, (char*)&lpc, sizeof(lpc), &lps, sizeof(lps));
		LOG("proof received. cmd %02x, code %02x\n", lps.cmd, lps.error);
		LOG("M2 %smatch.\n", memcmp(M2, lps.M2, 20) ? "mis" : "");
	}
}

// will result in silence unless the server considers us "authed".
static char* dumpRealmList(Socket sock, const char* targetRealmName) {
	sAuthRealmHeader_S rhs;
	char buf[6];
	buf[0] = CMD_REALM_LIST;
	LOG("dumpRealmList send...\n");
	sendAndReceiveExact(sock, buf, sizeof(buf), &rhs, sizeof(rhs));
	//DUMPINT(rhs.size);
	DUMPINT(rhs.count);
	{
		int rlSize = rhs.size-5;
		char* rlBuf = (char*)malloc(rlSize);
		char* ptr = rlBuf;
		receiveExact(sock, rlBuf, rlSize);
		for(int i=0; i<rhs.count; i++) {
			sAuthRealmEntry1_S* e1;
			sAuthRealmEntry2_S* e2;
			const char* name;
			char* address;
			e1 = (sAuthRealmEntry1_S*)ptr;
			ptr += sizeof(sAuthRealmEntry1_S);
			name = ptr;
			ptr += strlen(ptr) + 1;
			address = ptr;
			ptr += strlen(ptr) + 1;
			e2 = (sAuthRealmEntry2_S*)ptr;
			ptr += sizeof(sAuthRealmEntry2_S);
			assert(ptr - rlBuf <= rlSize);

			if(targetRealmName) {
				if(!strcmp(name, targetRealmName)) {
					// memory leak, but it's only one small buffer, so we don't care.
					return address;
				}
			} else {
				LOG("%i: %s (%s) p%f c%i t%i i%i f%02x\n", i, name, address,
					e2->popLevel, e2->charCount, e2->timezone, e1->icon, e1->flags);
			}
		}
		free(rlBuf);
	}
	return NULL;
}

static void connectToWorld(WorldSession* session, Socket authSock, const char* realmName) {
	char* colon;
	int port;
	const char* host;
	char* address = dumpRealmList(authSock, realmName);
	if(!address) {
		LOG("realm not found!\n");
		exit(1);
	}
	DUMPSTR(address);
	colon = strchr(address, ':');
	if(!colon) {
		port = DEFAULT_WORLDSERVER_PORT;
	} else {
		*colon = 0;
		port = strtol(colon + 1, NULL, 10);
	}
	host = address;
	session->sock = connectNewSocket(host, port);
}

static Socket connectNewSocket(const char* address, ushort port) {
	struct sockaddr_in clientService;
	uint32_t inetAddr;
	int res;
	int v;
	socklen_t len = sizeof(v);

	// create socket
	Socket sock = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
	if(sock == INVALID_SOCKET)
	{
		LOG("socket() returned error code %d\n", SOCKET_ERRNO);
		return INVALID_SOCKET;
	}

	LOG("connecting to %s:%i...\n", address, port);

	// disable Nagle's
	v = 1;
	res = setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (char*)&v, len);
	if(res == SOCKET_ERROR) {
		LOG("setsockopt() returned error code %d\n", SOCKET_ERRNO);
		return INVALID_SOCKET;
	}

	// resolve address
	inetAddr = inet_addr(CONFIG_SERVER_ADDRESS);
	if(inetAddr == INADDR_NONE) {
		struct hostent *hostEnt;
		if((hostEnt = gethostbyname(address)) == NULL) {
			LOG("DNS resolve failed. %d\n", SOCKET_ERRNO);
			return INVALID_SOCKET;
		}
		inetAddr = (uint32_t)*((uint32_t*)hostEnt->h_addr_list[0]);
		if(inetAddr == INADDR_NONE) {
			LOG("Could not parse the resolved ip address. %d\n", SOCKET_ERRNO);
			return INVALID_SOCKET;
		}
	}

	// connect
	clientService.sin_family = AF_INET;
	clientService.sin_addr.s_addr = inetAddr;
	clientService.sin_port = htons( port );
	res = connect(sock, (struct sockaddr*) &clientService, sizeof(clientService));
	if(SOCKET_ERROR == res)
	{
		LOG("connect() returned error code %d\n", SOCKET_ERRNO);
		return INVALID_SOCKET;
	}

	return sock;
}
