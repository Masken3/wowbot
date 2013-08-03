#include "socket.h"
#include "log.h"

int receiveExact(Socket sock, void* dst, size_t dstSize) {
	int remain = dstSize;
	char* dstP = (char*)dst;
	int res;
	//LOG("recv...\n");
	do {
		res = recv(sock, dstP, remain, 0);
		if (res > 0) {
			//printf("Bytes received: %d\n", res);
			remain -= res;
			dstP += res;
			continue;
		}
		if (res == 0) {
			printf("Connection closed\n");
		} else {
			printf("recv failed: %d\n", SOCKET_ERRNO);
		}
		return res;
	} while (remain > 0);
	return dstSize;
}

void sendExact(Socket sock, const char* src, size_t srcSize) {
	int res;
	//LOG("send %i\n", srcSize);
	res = send(sock, src, srcSize, 0);
	if(SOCKET_ERROR == res)
	{
		LOG("send() returned error code %d\n", SOCKET_ERRNO);
		exit(1);
	}
}

void sendAndReceiveExact(Socket sock, const char* src, size_t srcSize,
	void* dst, size_t dstSize)
{
	sendExact(sock, src, srcSize);
	if(receiveExact(sock, dst, dstSize) <= 0)
		exit(1);
}

Socket connectNewSocket(const char* address, ushort port) {
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
	inetAddr = inet_addr(address);
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
