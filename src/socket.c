#include "socket.h"
#include "log.h"

void receiveExact(Socket sock, void* dst, size_t dstSize) {
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
		if (res == 0)
			printf("Connection closed\n");
		else
			printf("recv failed: %d\n", SOCKET_ERRNO);
		exit(1);
	} while (remain > 0);
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
	receiveExact(sock, dst, dstSize);
}

