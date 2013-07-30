#include "config.h"
#include "socket.h"
#include "AuthCodes.h"
#include "AuthSocketStructs.h"
#include "AuthCalc.h"
#include "log.h"
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <assert.h>

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

static void receiveExact(Socket sock, void* dst, size_t dstSize) {
	int remain = dstSize;
	char* dstP = (char*)dst;
	int res;
	LOG("recv...\n");
	do {
		res = recv(sock, dstP, remain, 0);
		if (res > 0) {
			printf("Bytes received: %d\n", res);
			remain -= res;
			dstP += res;
			continue;
		}
		if (res == 0)
			printf("Connection closed\n");
		else
			printf("recv failed: %d\n", SOCKET_ERRNO);
		exit(1);
	} while (remain > 0);
}

static void sendAndReceiveExact(Socket sock, const char* src, size_t srcSize,
	void* dst, size_t dstSize)
{
	int res;
	res = send(sock, src, srcSize, 0);
	if(SOCKET_ERROR == res)
	{
		LOG("send() returned error code %d\n", SOCKET_ERRNO);
		exit(1);
	}
	receiveExact(sock, dst, dstSize);
}

static void authenticate(Socket sock) {
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

	CalculateLogonProof(&lcs, &lpc, CONFIG_ACCOUNT_NAME, CONFIG_ACCOUNT_PASSWORD, M2);
	// send proof
	{
		lpc.cmd = CMD_AUTH_LOGON_PROOF;
		sendAndReceiveExact(sock, (char*)&lpc, sizeof(lpc), &lps, sizeof(lps));
		LOG("proof received. cmd %02x, code %02x\n", lps.cmd, lps.error);
		LOG("M2 %smatch.", memcmp(M2, lps.M2, 20) ? "mis" : "");
	}
}

// will result in silence unless the server considers us "authed".
static void dumpRealmList(Socket sock) {
	sAuthRealmHeader_S rhs;
	char buf[6];
	buf[0] = CMD_REALM_LIST;
	LOG("dumpRealmList send...\n");
	sendAndReceiveExact(sock, buf, sizeof(buf), &rhs, sizeof(rhs));
	DUMPINT(rhs.size);
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
			const char* address;
			e1 = (sAuthRealmEntry1_S*)ptr;
			ptr += sizeof(sAuthRealmEntry1_S);
			name = ptr;
			ptr += strlen(ptr) + 1;
			address = ptr;
			ptr += strlen(ptr) + 1;
			e2 = (sAuthRealmEntry2_S*)ptr;
			ptr += sizeof(sAuthRealmEntry2_S);
			assert(ptr - rlBuf <= rlSize);

			LOG("%i: %s (%s) p%f c%i t%i i%i f%02x\n", i, name, address,
				e2->popLevel, e2->charCount, e2->timezone, e1->icon, e1->flags);
		}
	}
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
