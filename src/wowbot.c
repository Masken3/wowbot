#include "config.h"
#include "socket.h"
#include "AuthCodes.h"
#include "AuthSocketStructs.h"
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>

#define CONFIG_CHAR_RACE dorf
#define CONFIG_CHAR_CLASS warrior
#define CONFIG_CHAR_GENDER male

#define DEFAULT_WORLDSERVER_PORT 8085                       //8129
#define DEFAULT_REALMSERVER_PORT 3724

#define LOG printf

typedef uint16_t ushort;
typedef uint8_t byte;

static Socket connectNewSocket(const char* address, ushort port);
static void dumpRealmList(Socket sock);
static void authenticate(Socket sock);

int main(void) {
	Socket sock;

#ifdef WIN32
	{
		// Initialize Winsock
		WSADATA wsaData;
		int res = WSAStartup(MAKEWORD(2,2), &wsaData);
		if (res != 0) {
			printf("WSAStartup failed: %d\n", res);
			exit(1);
		}
	}
#endif

	LOG("Connecting...\n");
	sock = connectNewSocket(CONFIG_SERVER_ADDRESS, DEFAULT_REALMSERVER_PORT);
	if(sock == INVALID_SOCKET) {
		exit(1);
	}
	LOG("Connected.\n");

	authenticate(sock);
	dumpRealmList(sock);

	return 0;
}

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
	} while (res > 0);
}

static void authenticate(Socket sock) {
	{
		char buf[1024];
		sAuthLogonChallenge_C* p = (sAuthLogonChallenge_C*)buf;
		memset(p, 0, sizeof(*p));
		p->cmd = CMD_AUTH_LOGON_CHALLENGE;
		p->I_len = sizeof(CONFIG_ACCOUNT_NAME);
		p->size = sizeof(*p) + (p->I_len - 1) - 4;
		strcpy((char*)p->I, CONFIG_ACCOUNT_NAME);
		sendAndReceiveDump(sock, buf, p->size + 4);
		return;
	}
	{
		char buf[1 + sizeof(sAuthLogonProof_C)];
		buf[0] = CMD_AUTH_LOGON_PROOF;
		//sAuthLogonProof_C* p = (sAuthLogonProof_C*)(buf+1);
		sendAndReceiveDump(sock, buf, sizeof(buf));
	}
}

// will result in silence unless the server considers us "authed".
static void dumpRealmList(Socket sock) {
	char buf[6];
	buf[0] = CMD_REALM_LIST;
	LOG("dumpRealmList send...\n");
	sendAndReceiveDump(sock, buf, sizeof(buf));
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
